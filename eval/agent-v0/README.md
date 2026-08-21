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

## Why this is data-only in Sprint 1

This corpus intentionally has no automated runner yet — building one is Epic
E's job, not this Sprint's. Running it today is a manual procedure, but the
two paths have very different constraints:

- **Cloud path (OpenRouter)**: no physical device needed. Running the full
  corpus against a model costs real API credits (BYOK), but there is nothing
  technically stopping it from being scripted and automated later — Epic E's
  eval runner is expected to do exactly that against this same corpus,
  unchanged.
- **On-device path (Apple FoundationModels)**: requires a physical
  Apple-Intelligence-capable device (the simulator does not have the model).
  This constraint doesn't go away when Epic E's runner exists — on-device
  eval will always need a device in the loop, or a device farm.

## Manual execution (until Epic E)

1. Open the Agent sheet in the relevant `AgentContext` for cloud-path
   testing, or on a real device for on-device testing (see
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
