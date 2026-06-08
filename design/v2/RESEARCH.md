# ZeeChat v2.0 Research Synthesis

Date: 2026-06-07
Sources: 4 parallel audits (iOS codebase, PC dispatch backend, Mac PM shim, test suite)

## Key insights that change the ship plan

### 1. Daemon is unified, not Mac vs PC
Same `dispatch` package runs on both Mac (role=pm) and PC (role=swe). One PR
adds the v2.0 wire fields + endpoints to both simultaneously. Saves the Mac
PM shim catchup work I scoped originally.

### 2. Refine handler lives in the Claude agent, not the daemon
Daemon just routes `kind="refine_request"` opaquely. The Mac PM Claude
session reads its inbox, sees `kind=refine_request + refine_id + body`,
processes (re-prompts via own context), dispatches `kind=refine_response`
with same refine_id. Daemon never needs to know what refine means.

Implication: backend scope drops from "implement refine handler" to
"add 4 optional columns + accept-then-route." ~5.5h total backend work
(was estimated 5-6h, confirmed tight).

### 3. iOS has ZERO tests + ZERO CI
Current ZeeChat v1.3 shipped with no test target. Highest-risk v2.0 paths
(DraftStore atomic write, RefineCoordinator refine_id matching, audio session
state machine) MUST be TDD'd or we ship blind.

Phase 0 must include: add ZeeChatTests/ target + GitHub Actions workflow
+ first passing test before any feature code lands.

### 4. Schema migration is simpler than expected
No Alembic on dispatch. db.py:_SCHEMA_SQL is one CREATE TABLE script. Adding
columns = append `_migrate_schema_v2()` hook with ALTER TABLE + DEFAULT
values. Old messages still load. ~30 min, not days.

### 5. Attachment infra is full greenfield
No upload/serving/storage exists. Needs: `POST /api/attachments/upload`,
`GET /api/attachments/{msg_id}/{filename}`, `~/.dispatch/attachments/`
storage, cleanup hook in db.prune(). ~2h SWE work.

### 6. Theme rewrite is total
Current Theme.swift is "Tailnet Terminal" — monospace SF Mono everywhere,
hard 2pt corners, DotGrid Canvas, [BRACKETED] pills, saturated cyan/magenta
borders. Soft v2.0 palette is full rewrite, not evolution. Snapshot baselines
must lock immediately after first install so CEO eyeball can be diffed later.

## Risk-ranked v2.0 test plan (TDD-first)

| Rank | Area | Test before code? | Why |
|---|---|---|---|
| 1 | RefineCoordinator refine_id matching + timeout | YES | Async, race-prone, silent failure mode |
| 2 | DraftStore atomic write + corrupt-file fallback | YES | Persistence, app-kill-during-write |
| 3 | Voice-call audio session + interrupt + STT reactivation | YES | Complex audio state machine |
| 4 | AttachmentClient HEIC→JPEG thumbnail round-trip | YES | Format conversion, network |
| 5 | ZeeCloud draft sync conflict resolution | YES | Race condition on multi-device |
| 6 | Spec composer UI layout | SNAPSHOT | Can't TDD layout |
| 7 | Theme tokens + DotGrid removal | SNAPSHOT | Lock baseline at first install |
| 8 | Compact mode toggle state | SNAPSHOT | Pure local UI state |

## Updated ship order

**P0 (visual + test infra):** 6h iOS
- Add ZeeChatTests/ target to project.yml + xcodegen regen
- Add `.github/workflows/test.yml` running `xcodebuild test`
- Theme.swift rewrite (soft palette, 18pt corners, gradient bg, SF Pro body, drop DotGrid)
- ChatView visual pass (capsule pills, edge bar instead of border, no `>`/`<` glyphs)
- First snapshot baseline locked after CEO eyeball

**P1 (spec composer + draft sync + refine):** 8h iOS + 4h backend
- TDD DraftStore (atomic write, corrupt fallback, ZeeCloud sync)
- TDD RefineCoordinator (refine_id state, multiple-in-flight, 30s timeout)
- SpecComposerView modal sheet
- Mac PM + PC SWE Claude agents handle kind=refine_request
- Backend adds kind/attachment_url/attachment_preview/refine_id columns + draft endpoints

**P2 (voice dictation + image attach):** 6h iOS + 2h backend
- TDD VoiceRecognizer (SFSpeechRecognizer wrapper, error states)
- TDD AttachmentClient (HEIC→JPEG, thumbnail, upload, fetch)
- Composer + spec sheet mic buttons
- Backend adds attachment upload/serve endpoints + storage

**P3 (voice-call mode):** 8h iOS
- TDD SpeechSynthesizer + AVAudioSession state machine + interrupt handling
- VoiceCallView full-screen modal
- VAD silence flush logic
- Tap-to-interrupt + STT reactivation

Total v2.0: ~28h iOS + ~6h backend (PC + Mac via unified daemon). Was 25h estimated, +3h for test infra prep.

## Open questions resolved by audits

| Question | Resolution |
|---|---|
| Mac PM shim catchup work? | Not needed — unified repo, one PR ships to both |
| Refine daemon-level handler? | No — agents handle it, daemon just routes |
| Schema migration complexity? | Trivial — append `_migrate_schema_v2()` hook |
| iOS test infra cost? | ~1h to add target + CI |
| Voice-call risk? | Highest in v2.0 — must TDD |

## Ship-gate dashboard

Per-phase install to phone + automated baseline check + CEO eyeball:
- P0 ships: Theme snapshot baseline + first test passing on CI + visual softness reads as intended
- P1 ships: 1 spec round-trips through PM, draft survives app kill, refine returns within 30s
- P2 ships: voice dictation transcribes 5s phrase, image attaches with preview
- P3 ships: 30s voice convo with PM Claude works including interrupt
