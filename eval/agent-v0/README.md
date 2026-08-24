# Agent v0 behavior baseline corpus

38 cases across 6 files, establishing what the current Agent (before Sprint 1's
validation-boundary work) actually does with a representative set of Korean
prompts — the reference point for measuring whether later changes (this
Sprint, or the model swaps in Epic F) are actual improvements.

## Schema

```json
{
  "id": "create-001",
  "category": "simple-create",
  "input": "내일 오후 3시에 치과 일정 추가해줘",
  "expectedBehavior": "PROPOSE_SCHEDULE",
  "expected": { "date": "tomorrow", "startTime": "15:00", "isTask": false },
  "notes": "basic relative-date create"
}
```

- `expectedBehavior` is one of: `SEARCH_SCHEDULES`, `FIND_FREE_SLOTS`,
  `PROPOSE_SCHEDULE`, `PROPOSE_SCHEDULE_UPDATE`, `ANSWER` (no tool call —
  plain-text reply, including cases where the model should ask a follow-up
  question instead of guessing), `UNSUPPORTED` (no tool covers the request).
  **These are canonical evaluation labels only, not a runtime enum** — Sprint
  1 deliberately does not introduce a full `AgentIntent` union in code (see
  `docs/20-ai-agent-architecture.md` §5-1 and the Sprint 1 plan); don't treat
  a case passing here as evidence that this taxonomy already exists as a
  type anywhere in `agent-cloud-contract.ts` or `AgentTools.swift`.
- `expected` is optional and partial — fill in only the fields worth pinning
  down for that case. An empty `{}` is fine.
- `notes` explains why the case is interesting, not what it does.

## Cloud path: automated via Epic E's runner

Epic E added an automated runner for the cloud path — `memdo-backend`'s
`eval/run.ts` (`npm run eval` from that repo). It POSTs each fixture's
`input` to the deployed `agent-cloud-chat` function fresh (no history),
reads back which tool(s) actually got dispatched
(`ToolDispatchState.dispatchedTools`, added in the same Epic), and grades
the result against `expectedBehavior`/`expected` via `eval/grade.ts`'s pure
`gradeCase()`.

Needs a real logged-in user's Supabase access token (with an OpenRouter key
already connected via the app's normal connect flow) in
`SUPABASE_ACCESS_TOKEN` — every run spends real OpenRouter credits, so this
never runs in CI, only manually. See `memdo-backend/eval/run.ts`'s header
comment for the exact invocation.

Coverage isn't 100%: `ANSWER`/`UNSUPPORTED` (10 of 38 cases) can't be told
apart from each other purely from whether a tool was called — both look
like "no tool, some text" from the outside — so those come back as
`manual-review` with the model's actual response text attached, not an
automatic pass/fail. That's an inherent limit of grading from the outside,
not something a bigger corpus or a smarter grader fixes.

### State-dependent fixtures: seeded via Epic F-1

`PROPOSE_SCHEDULE_UPDATE` fixtures (`search-005`, `search-006`) need a real
pre-existing schedule in whatever account the runner's token belongs to —
`search_schedules` has nothing to find otherwise, and
`propose_schedule_update` never gets called regardless of how good the
model is. Epic F-1 closed this: run `npm run eval:seed`
(`memdo-backend/eval/seed.ts`) once against the dedicated eval account
**before** `npm run eval` — it upserts exactly the 2 rows these fixtures
need (deterministic ids, so re-running it always restores them to the same
title/date even if something else touched them since). `run.ts` no longer
routes these to `skipped`; they're graded like every other case.

**What this does and doesn't guarantee**: `eval:seed` only restores its own
2 rows. It does **not** wipe or otherwise touch any other, unrelated todo
that might exist in that account — running it does not make the account
"clean," only those 2 specific rows deterministic. That's enough for
search-005/006 (nothing else in the corpus depends on the account's
broader state).

Required env vars for both `eval:seed` and `eval`: `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_ACCESS_TOKEN` (the dedicated eval
account's token). The backend additionally needs `MEMDO_EVAL_SEED_ENABLED=true`
and `MEMDO_EVAL_ACCOUNT_USER_ID` (that account's user id) set on the
deployment — see `memdo-backend/supabase/functions/eval-bootstrap/index.ts`.

### Comparing multiple models: `eval:compare` (Epic F-2)

`memdo-backend`'s `eval/compare.ts` (`npm run eval:compare` from that repo)
runs the full corpus once per model — by default every model in
`ALLOWED_OPENROUTER_MODELS` — and reports pass/fail/manual-review plus
cost/tokens/wall-clock time side by side, so different models can actually
be compared on the same corpus.

F-1 left an open question here: would multi-model comparison need the eval
account kept fully isolated, or a real wipe/reset step? It doesn't. The
Agent never writes to `todos` directly (`docs/20-ai-agent-architecture.md`
§2) — `propose_schedule`/`propose_schedule_update` only stage a proposal
for the user to approve, and `eval run`/`eval:compare` never approve
anything — so a comparison run has no way to leave state behind beyond
what `eval:seed` already seeds. Cost/token attribution reads
`agent_usage_log` directly, scoped per model by an id watermark taken
right before that model's run, not by account "cleanliness."

**Rate limiting**: `agent-cloud-chat` caps every account at 30 requests/hour
by default, which a single model run against this 38-case corpus already
exceeds — comparing multiple models needs the dedicated eval account's
limit raised. On the backend, set `MEMDO_EVAL_RATE_LIMIT_ENABLED=true` and
`MEMDO_EVAL_RATE_LIMIT_PER_HOUR` to a value **strictly greater than 30**
(e.g. `250`) — this only ever raises the limit for the one account matching
`MEMDO_EVAL_ACCOUNT_USER_ID`; every other account's 30/hour limit is
unaffected regardless of these settings. Hitting the limit mid-comparison
is expected, not a bug: `eval:compare` does not auto-retry or sleep past a
429 — it stops the whole comparison at that point and saves the partial
results collected so far (including the model that got rate-limited);
rerun the remaining models later with `--models`.

**Do not run anything else against the eval account while `eval:compare`
(or `eval`) is running** — no manual app usage, no parallel `eval`/`eval:compare`
run. Cost/token attribution is scoped per model by an id watermark, which
eliminates any dependency on client/DB clock agreement, but it still can't
tell apart two concurrent calls to the *same* model — those would mix
their usage into the same model's totals and produce an incorrect
cost/token comparison.

See `memdo-backend/eval/compare.ts`'s header comment for the exact
invocation and flags (`--models`, `--fixtures`, `--json`).

## On-device path: still manual

Requires a physical Apple-Intelligence-capable device (the simulator does
not have the model) — this constraint doesn't go away with Epic E's runner,
since on-device eval will always need a device in the loop, or a device
farm, not an HTTP endpoint. Still a manual procedure:

1. Open the Agent sheet in the relevant `AgentContext` on a real device (see
   `docs/32-agent-manual-test-plan.md` for the general manual-testing
   pattern this follows).
2. Paste each `input` value in, one at a time, in a fresh conversation
   (so prior turns don't bias tool selection).
3. Record which tool was called (if any) and its arguments, or that the
   model answered in plain text.
4. Compare against `expectedBehavior`/`expected`. A mismatch isn't
   necessarily a bug — some cases (`temporal-005` through `temporal-008`,
   the `ambiguity-*` file) are deliberately hard or have no single correct
   answer; they exist to characterize behavior, not to gate a release.
