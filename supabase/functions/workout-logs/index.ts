import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, idempotency-key, x-request-id",
};

// ── Types ─────────────────────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Row = Record<string, any>;

// Maps workout_log_full view row → camelCase DTO that iOS WorkoutLogResponseDTO expects.
function toDTO(row: Row) {
  return {
    id:             row.id,
    hkUuid:         row.hk_uuid      ?? null,
    source:         row.source,
    activityType:   row.activity_type,
    startedAt:      row.started_at,
    endedAt:        row.ended_at,
    durationSec:    row.duration_sec,
    distanceM:      row.distance_m    ?? null,
    calories:       row.calories      ?? null,
    avgHeartRate:   row.avg_heart_rate ?? null,
    routeImageUrl:  row.route_image_url ?? null,
    photoUrl:       row.photo_url     ?? null,
    scheduledDate:  row.scheduled_date,
    locationName:   row.location_name ?? null,
    notes:          row.notes         ?? "",
    exercises:      row.exercises     ?? null,
  };
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse(401, "UNAUTHORIZED", "Authorization header required");
  }
  const { data: { user }, error: authError } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", "")
  );
  if (authError || !user) {
    return errorResponse(401, "UNAUTHORIZED", "Invalid token");
  }

  const url = new URL(req.url);

  // Route: /workout-logs/{id}/details  (PATCH)
  const detailsMatch = url.pathname.match(/\/workout-logs\/([0-9a-f-]{36})\/details$/i);
  if (detailsMatch && req.method === "PATCH") {
    return handleUpdateDetails(supabase, user.id, detailsMatch[1], req);
  }

  // Route: /workout-logs  (GET | POST)
  if (req.method === "GET")  return handleList(supabase, user.id, url);
  if (req.method === "POST") return handleCreate(supabase, user.id, req, req.headers.get("Idempotency-Key"));

  return errorResponse(405, "METHOD_NOT_ALLOWED", "Method not allowed");
});

// ── GET /workout-logs?from=YYYY-MM-DD&to=YYYY-MM-DD ──────────────────────────

async function handleList(supabase: ReturnType<typeof createClient>, userId: string, url: URL) {
  const from = url.searchParams.get("from");
  const to   = url.searchParams.get("to");
  if (!from || !to) {
    return errorResponse(400, "BAD_REQUEST", "from and to query params required");
  }

  const { data, error } = await supabase
    .from("workout_log_full")
    .select("*")
    .eq("user_id", userId)
    .gte("scheduled_date", from)
    .lte("scheduled_date", to)
    .order("started_at", { ascending: false });

  if (error) return errorResponse(500, "DB_ERROR", error.message);
  return jsonResponse({ items: (data ?? []).map(toDTO) });
}

// ── POST /workout-logs ────────────────────────────────────────────────────────

async function handleCreate(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  req: Request,
  _idempotencyKey: string | null
) {
  const body = await req.json().catch(() => null);
  if (!body) return errorResponse(400, "BAD_REQUEST", "JSON body required");

  const {
    hkUuid, source, activityType, startedAt, endedAt,
    durationSec, distanceM, calories, avgHeartRate,
    routeImageUrl, photoUrl, scheduledDate,
    locationName, notes, exercises
  } = body;

  if (!activityType || !startedAt || !endedAt || !durationSec || !scheduledDate) {
    return errorResponse(400, "BAD_REQUEST", "Missing required fields");
  }

  // Idempotency: return existing if same hk_uuid already recorded for this user
  if (hkUuid) {
    const { data: existing } = await supabase
      .from("workout_log_full")
      .select("*")
      .eq("user_id", userId)
      .eq("hk_uuid", hkUuid)
      .maybeSingle();
    if (existing) return jsonResponse(toDTO(existing), 200);
  }

  const { data: log, error: logError } = await supabase
    .from("workout_logs")
    .insert({
      user_id:         userId,
      hk_uuid:         hkUuid        ?? null,
      source:          source        ?? "manual",
      activity_type:   activityType,
      started_at:      startedAt,
      ended_at:        endedAt,
      duration_sec:    durationSec,
      distance_m:      distanceM     ?? null,
      calories:        calories      ?? null,
      avg_heart_rate:  avgHeartRate  ?? null,
      route_image_url: routeImageUrl ?? null,
      photo_url:       photoUrl      ?? null,
      scheduled_date:  scheduledDate,
    })
    .select("id")
    .single();

  if (logError) {
    // Handle unique constraint violation on hk_uuid (race condition)
    if (logError.code === "23505" && hkUuid) {
      const { data: existing } = await supabase
        .from("workout_log_full")
        .select("*")
        .eq("user_id", userId)
        .eq("hk_uuid", hkUuid)
        .maybeSingle();
      if (existing) return jsonResponse(toDTO(existing), 200);
    }
    return errorResponse(500, "DB_ERROR", logError.message);
  }

  // Details insert is non-fatal — the view uses COALESCE for missing rows.
  const { error: detailError } = await supabase
    .from("workout_log_details")
    .insert({
      workout_log_id: log.id,
      location_name:  locationName ?? null,
      notes:          notes        ?? "",
      exercises:      exercises    ?? null,
    });

  if (detailError) console.error("workout_log_details insert failed:", detailError.message);

  const { data: full, error: readError } = await supabase
    .from("workout_log_full")
    .select("*")
    .eq("id", log.id)
    .single();

  if (readError) return errorResponse(500, "DB_ERROR", readError.message);
  return jsonResponse(toDTO(full), 201);
}

// ── PATCH /workout-logs/{id}/details ─────────────────────────────────────────

async function handleUpdateDetails(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  workoutId: string,
  req: Request
) {
  const { data: parent, error: parentError } = await supabase
    .from("workout_logs")
    .select("id")
    .eq("id", workoutId)
    .eq("user_id", userId)
    .maybeSingle();

  if (parentError) return errorResponse(500, "DB_ERROR", parentError.message);
  if (!parent) return errorResponse(404, "NOT_FOUND", "Workout not found");

  const body = await req.json().catch(() => null);
  if (!body) return errorResponse(400, "BAD_REQUEST", "JSON body required");

  const { locationName, notes, exercises } = body;

  const { error: upsertError } = await supabase
    .from("workout_log_details")
    .upsert({
      workout_log_id: workoutId,
      location_name:  locationName ?? null,
      notes:          notes        ?? "",
      exercises:      exercises    ?? null,
      updated_at:     new Date().toISOString(),
    }, { onConflict: "workout_log_id" });

  if (upsertError) return errorResponse(500, "DB_ERROR", upsertError.message);

  const { data: full, error: readError } = await supabase
    .from("workout_log_full")
    .select("*")
    .eq("id", workoutId)
    .single();

  if (readError) return errorResponse(500, "DB_ERROR", readError.message);
  return jsonResponse(toDTO(full));
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(status: number, code: string, message: string) {
  return new Response(JSON.stringify({ error: { code, message } }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
