# ZeeChat Roadmap — Conversation Studio → Phone Dev Cockpit

Date: 2026-06-07
Owner: CEO (vision), PM Mac (iOS), SWE PC (backend), PM Mac (dispatch shim)
Scope: 7 versions (v2.0–v2.6), 28 features (1 locked + 27 brainstormed)

---

## Tier-up arc

- **v2.0 Conversation Studio** — visual refresh + composer foundations. LOCKED.
- **v2.1 Spec Studio** — make writing a spec 5× faster than typing one.
- **v2.2 Phone-First Cockpit** — at-a-glance status; never wonder "is it shipping?"
- **v2.3 Ship From Phone** — review + approve + install + verify, no laptop.
- **v2.4 AI Co-author** — Claude helps you write specs while you write them.
- **v2.5 Ambient Input** — voice + Watch + lock screen for hands-free spec capture.
- **v2.6 Meta-Orchestration** — multi-agent routing, slash commands, cross-app intent.

Total est. effort if shipped end-to-end: ~120h iOS, ~40h PC, ~15h Mac shim. Shipped per version, no big-bang.

Per-version ship gate: CEO eyeball on the live phone build + 1 representative spec sent through the new flow. No version ships without passing.

---

## v2.0 Conversation Studio — LOCKED (15-17h iOS, 5-6h PC, 3h Mac shim)

See `SPEC-LOCKED.md`. Items: visual refresh, spec composer, voice dictation, voice-call mode, image attach, draft sync, refine round-trip.

Ship gate: CEO sends 1 spec, has 1 voice-call exchange, attaches 1 image. All round-trip cleanly.

---

## v2.1 Spec Studio (16h iOS, 2h PC, 0h Mac shim)

Goal: writing a spec should take 20 seconds, not 90.

| # | Feature | iOS | PC | Files | Depends on |
|---|---|---|---|---|---|
| 4 | **Spec templates** | 2h | 0 | `Views/SpecComposerView.swift` + `Templates/*.md` | v2.0 spec composer |
| 5 | **Photo-to-spec** | 3h | 1h | `Services/PhotoSpecCoordinator.swift`, `Networking/AttachmentClient.swift` | v2.0 image attach |
| 6 | **Spec library** | 3h | 1h | `Storage/SpecLibrary.swift`, new `Views/SpecLibraryView.swift` tab | v2.0 draft sync |
| 7 | **Spec linter** | 2h | 0 | `Services/SpecLinter.swift` | none |
| 8 | **Refine-with-mode** | 2h | 0 | `Views/SpecComposerView.swift` sub-menu | v2.0 refine round-trip |
| | Tests + polish | 4h | 0 | snapshot tests, lint rule tests | |

**Per-item scope:**

**#4 Spec templates** — 6 templates: bugfix / feature / refactor / test / blocker / question. Each is a Markdown file in `Templates/` bundled with the app. Spec composer gets a "+" button before the body field that pops a template picker. Pick → body is populated with skeleton (Markdown headers + placeholder bullets). Voice-fill any section directly. Templates editable in Settings → Spec Templates (synced to ZeeCloud). Acceptance: 6 templates baked + 1 user-created template round-trips through sync.

**#5 Photo-to-spec** — In spec composer, paperclip → "Photo for spec". Take photo OR pick from library. iOS runs Vision OCR (`VNRecognizeTextRequest`), pulls visible text into a quote block at the top of the spec body. Image attaches to the eventual dispatched message. Voice button can be used to dictate context around the photo. Acceptance: screenshot of a UI bug → OCRed text + image both arrive on PM side.

**#6 Spec library** — Sent specs (kind=spec) are auto-saved to a `SpecLibrary` table. New "Specs" tab in main nav: list of past specs with target chip, send date, outcome status (sent → in-progress → shipped/abandoned). Tap to view + "Clone" button populates a fresh spec composer. Outcome status updates when PM/SWE dispatches a `kind="spec_outcome"` reply. Acceptance: send a spec, then clone it 2 days later.

**#7 Spec linter** — Pure-Swift rule set. Before "Send spec", lint runs. Rules: "no acceptance criteria" (no `## Acceptance` heading or no bullets after it), "no target specified" (target chip blank), "vague verbs" (only contains "fix", "do", "make"), "no scope marker" (no mention of iOS/backend/both), "less than 30 chars" (probably under-specified). Soft warnings; "Send anyway" overrides. Toggle in Settings. Acceptance: ship with 5 rules, all surfaceable in the composer.

**#8 Refine-with-mode** — Refine button becomes a long-press → 4 modes (Tighten / Add detail / Make TDD / Add rollback). Each mode sends a different system prompt to the receiving Claude. Default tap = current generic refine. Acceptance: each of 4 modes produces a distinctly different refined output on the same input.

Ship gate v2.1: CEO writes a spec from a template in <30s, uses photo-to-spec once, clones a past spec, hits a lint warning + dismisses, refines with "make TDD" once. All work.

---

## v2.2 Phone-First Cockpit (12h iOS, 6h PC, 2h Mac shim)

Goal: open ZeeChat and immediately know what's happening across all your apps + claudes.

| # | Feature | iOS | PC | Mac | Depends on |
|---|---|---|---|---|---|
| 1 | **Live activity feed** | 2h | 2h | 1h | new heartbeat dispatch kind |
| 2 | **All-systems dashboard** | 3h | 2h | 1h | heartbeat + per-app health endpoints |
| 3 | **Pending decisions inbox** | 2h | 1h | 0 | per-dispatch "awaiting_decision" flag |
| 17 | **Smart digest mode** | 2h | 1h | 0 | new notification grouping logic |
| 18 | **Priority routing** | 1h | 0 | 0 | existing `priority` field already on wire |
| 19 | **Mute by topic** | 2h | 0 | 0 | client-side filter + topic tag on send |

**Per-item scope:**

**#1 Live activity feed** — Mac PM + PC SWE dispatchers emit `kind="heartbeat"` every 60s with current activity ("editing ChatView.swift line 42", "pytest running 412/661", "idle"). ZeeChat renders a single-line ticker above the chat list: "PM • editing • 30s ago / SWE • pytest 412/661 • 5s ago". Tap to expand into full state. Tickers timeout after 5min of no heartbeat → "no signal" state. Acceptance: ticker updates within 90s of activity change on PM side.

**#2 All-systems dashboard** — New "Status" tab. One card per app (WC backend, WC iOS, CH backend, CH iOS, ZeeChat backend, Walkman sync, Dispatch). Each card: green/yellow/red dot, 1-line summary ("v2.3.1 healthy / 649 tests / 12 logs/min"). Per-app health endpoints: `/health` already on WC + CH; add for Walkman + Dispatch. Tap card → details view with last 5 errors / open tasks / open dispatches. Acceptance: dashboard live + accurate within 30s of an actual failure.

**#3 Pending decisions inbox** — Dispatch wire adds `awaiting_decision: bool`. Messages flagged true surface in a "Decisions" rail at the top of ZeeChat home. Ranked by priority + age. Tap → reply directly. Auto-clears on reply. Acceptance: SWE sends `awaiting_decision=true`, ZeeChat surfaces it in the rail within seconds.

**#17 Smart digest mode** — Per-target setting: instant (every message → ping) vs digest (batch every 15min → "PM: 3 ship confirms, 1 decision needed"). Default: instant during 9am-9pm local, digest outside. Configurable. Implementation: iOS background task queries dispatch inbox every 15min in digest hours, aggregates, posts a single local notification. Acceptance: 5 messages outside digest hours → 1 ping with summary.

**#18 Priority routing** — Already wire-supported (`priority: high|normal|low`). Add iOS UI: per-target setting for "min priority to ping me". Default: `high` always pings, `normal` follows digest, `low` no ping. Acceptance: low-priority message never pings.

**#19 Mute by topic** — Topic tag added to message wire (`topic: str | None`). ZeeChat lets CEO mute by topic from the chat row (long-press → "mute topic WC v2.4 for 2d/until set"). Filter applied client-side: muted messages still arrive, just no ping + collapsed in list. Acceptance: mute "Walkman", get 0 Walkman pings for the mute duration.

Ship gate v2.2: CEO opens ZeeChat after a 4h gap, sees the Status tab + Decisions rail + digest notification, all coherent.

---

## v2.3 Ship From Phone (13h iOS, 6h PC, 1h Mac shim)

Goal: review code + approve merge + install + verify, all from phone.

| # | Feature | iOS | PC | Mac | Depends on |
|---|---|---|---|---|---|
| 9 | **Inline diff review** | 5h | 2h | 1h | new `kind=review_request` |
| 10 | **Lock-screen actions** | 2h | 0 | 0 | UNNotification action category |
| 11 | **One-tap install** | 2h | 2h | 0 | Mac PM exposes build+install endpoint over Tailscale |
| 16 | **@ mentions in spec** | 4h | 2h | 0 | resolver service + file-context fetcher |

**Per-item scope:**

**#9 Inline diff review** — PM/SWE sends `kind="review_request"` with `{commit_sha, summary, diff_url, target_branch}`. ZeeChat fetches the diff via the PR/branch URL (or Tailscale-internal git proxy). Renders with `Splash` (Swift syntax highlighter) per hunk. Per-hunk thumbs up / inline comment / overall approve+merge / overall request-changes. Approval dispatches `kind="review_decision"` back. Acceptance: PM sends a diff, CEO approves from phone, PM auto-runs the merge.

**#10 Lock-screen actions** — `UNNotificationActionCategory` with "Approve" / "Reject" / "Snooze 1h" actions on notifications flagged `awaiting_decision`. Actions fire directly to the dispatch backend without launching the app. Acceptance: notification fires while phone locked, tap Approve, dispatch records the decision.

**#11 One-tap install** — Slash command `/install WC` in the PM chat triggers Mac PM to run `xcodebuild + devicectl device install`. Existing infra; just needs the slash-command listener on Mac PM + a confirmation reply to ZeeChat ("installed v99 to your phone"). Acceptance: `/install ZeeChat` from your phone → new ZeeChat build on your phone in <3min.

**#16 @ mentions** — In spec composer, typing `@` opens a 3-tab picker: Files (search across all known repos), Errors (recent log lines), Workouts (WC IDs). Resolves at dispatch-time: PM/SWE receives the spec with the referenced file's contents inline (truncated to 200 lines if huge). Acceptance: `@WC iOS Models/UserStats.swift line 21` arrives at PM with the actual file context, no separate "go look at this" call needed.

Ship gate v2.3: CEO reviews + merges 1 real PR from phone, installs the resulting build via /install, verifies it works. End-to-end review-to-running in <10min.

---

## v2.4 AI Co-author (10h iOS, 3h PC, 1h Mac shim)

Goal: Claude is your spec-writing co-pilot, not a downstream consumer.

| # | Feature | iOS | PC | Mac | Depends on |
|---|---|---|---|---|---|
| 15 | **Smart autocomplete in spec body** | 4h | 2h | 1h | dispatch supports `kind="suggest"` with low-latency |
| 20 | **Memory inspector** | 3h | 1h | 0 | new read endpoints on PM + SWE memory dirs |
| 21 | **"What did we ship today?" digest** | 3h | 0 | 0 | git log aggregator + dispatch summary |

**Per-item scope:**

**#15 Smart autocomplete** — As CEO types in spec body, ZeeChat debounces 600ms then dispatches `kind="suggest"` to selected target with current draft. Receiving Claude returns 3 short continuation suggestions. iOS renders inline grey suggestion → Tab to accept, type-anything to dismiss. Latency target: <1s round-trip on a warm Claude session. Privacy: suggestions stay client-side, don't post until accepted. Acceptance: typing 3 prefix words yields 3 plausible continuations within 1s in 80% of attempts.

**#20 Memory inspector** — New "Memory" subview under each chat (PM, SWE). Lists current memory entries from `~/.claude/projects/.../memory/`. Each entry: title + 1-line description + type. Tap → read full body. Edit / delete actions dispatch a write-back to the host Mac/PC. Refusal on attempted edit if memory is read-only (e.g. CLAUDE.md). Acceptance: CEO reads PM's memory, edits one entry, change persists on Mac.

**#21 What did we ship today** — At 9pm local (configurable), iOS background task fetches: git log across all 5 repos (commits today by author=PM or SWE), dispatch outcome states (specs marked shipped/abandoned), test run summaries. Composes a structured summary notification. Tap → full report view. Acceptance: at 9pm, CEO gets a useful summary with no manual prompt.

Ship gate v2.4: CEO writes a spec using autocomplete (accepting at least one suggestion), inspects + edits a memory entry, gets a daily digest at 9pm.

---

## v2.5 Ambient Input (18h iOS, 0h PC, 0h Mac shim)

Goal: hands-free spec capture from anywhere — walking, driving, lifting, sleeping.

| # | Feature | iOS | Notes |
|---|---|---|---|
| 12 | **Walking/driving mode** | 6h | CarPlay integration + motion detection + audio-only UI |
| 13 | **Voice journal** | 4h | Separate-from-spec audio capture + transcribe + browse + convert |
| 14 | **Apple Watch companion app** | 8h | Watch-OS target, voice → spec → dispatch, "send to last target" |

**Per-item scope:**

**#12 Walking/driving mode** — Auto-detects via Core Motion (sustained walking pace > 3mph or CarPlay connection). Switches to audio-only mode: incoming dispatches read aloud via TTS (using the v2.0 SpeechSynthesizer), CEO dictates back continuously. Visual UI hidden by default; just a "stop" button. CarPlay shows a single dedicated tile. Acceptance: 5min walk → 1 incoming dispatch read aloud + 1 outgoing dictated.

**#13 Voice journal** — New "Journal" tab. Big mic button = start recording. Records continuously, transcribes via on-device Whisper-equivalent. Saves as a journal entry (audio + transcript). Browse + search by transcript. Per-entry "Convert to spec" → opens spec composer pre-populated with the transcript. Acceptance: 60s ramble → searchable entry + convertable to spec.

**#14 Apple Watch app** — Standalone WatchOS target. Faces: Recent chats / Voice memo (long-press complication) / Dispatch to last target. Voice memo records → transcribes → dispatches via paired iPhone's ZeeChat. Acceptance: from watch, voice-memo a 15s spec → arrives on PM Mac.

Ship gate v2.5: CEO does a 10min walk with phone in pocket, dictates 2 specs + receives 1, doesn't touch the screen.

---

## v2.6 Meta-Orchestration (16h iOS, 8h PC, 4h Mac shim)

Goal: ZeeChat becomes the conductor — multi-agent specs, slash commands, cross-app awareness.

| # | Feature | iOS | PC | Mac |
|---|---|---|---|---|
| 22 | **Active sub-agent dashboard** | 3h | 2h | 1h |
| 23 | **Read iOS logs from chat** | 2h | 2h | 1h |
| 24 | **Slash commands** | 3h | 2h | 1h |
| 25 | **Cross-app intent capture** | 2h | 1h | 0 |
| 26 | **Round-trip specs** | 3h | 1h | 1h |
| 27 | **Conditional dispatch** | 3h | 0 | 0 |

**Per-item scope:**

**#22 Active sub-agent dashboard** — Mac PM + PC SWE periodically dispatch `kind="agent_status"` for each spawned Agent (`subagent_type`, `description`, started_at, status). ZeeChat shows a collapsed list "3 PM agents running, 1 SWE". Expand to see each + kill / peek output. Acceptance: spawning an Explore agent on Mac → visible in ZeeChat within 5s.

**#23 Read iOS logs from chat** — Slash command `/logs WC last 5min` triggers Mac to run `idevicesyslog | filter | tail`, returns formatted log lines as a reply. Same for `/logs CH`, `/logs ZeeChat`. Logs render with syntax highlighting for level (error red, warn yellow). Acceptance: from gym, `/logs WC last 1min` returns the most recent iOS console output for WC.

**#24 Slash commands** — Composer recognizes `/`-prefix as a slash command. Built-in: `/install <app>`, `/restart <service>`, `/logs <app>`, `/seed <table>`, `/dispatch <target> <text>`, `/spec <template>`. Extensible: each command is a Swift type implementing `SlashCommand` protocol. Acceptance: ship with 6 commands, all execute successfully end-to-end.

**#25 Cross-app intent capture** — In Walkman app, "Remember this clip" button surfaces a dispatch via shared App Group → ZeeChat enqueues a Walkman tag-fix task. Same pattern works for WC ("flag this set for review") and CH ("expand on this craving log"). Acceptance: from Walkman now-playing, "Remember this clip" creates a properly-tagged spec in ZeeChat's Specs tab.

**#26 Round-trip specs** — Spec composer's target chip becomes "PM → SWE → me" (chain). Spec dispatches to PM first; PM's reply auto-forwards to SWE; SWE's reply auto-consolidates back to CEO with both perspectives. Implementation: new `kind="chain_spec"` with `chain: ["pm", "swe", "ceo"]` in metadata. Each Claude handler reads the chain, processes, dispatches to next. Acceptance: send a chain spec, get a consolidated final reply with 2 perspectives.

**#27 Conditional dispatch** — Spec composer has an "If…then…" block. "If PM doesn't reply within 30min, route to SWE." "If SWE estimates >4h, ask CEO before starting." Lightweight DSL: `IF <condition> THEN <action>`. Conditions: `no_reply_in(<duration>)`, `reply_contains(<word>)`, `estimate_gt(<hours>)`. Actions: `dispatch_to(<target>)`, `notify(<urgency>)`, `cancel`. Acceptance: ship with 3 conditions + 3 actions, all combinable.

Ship gate v2.6: CEO sends 1 chain spec + 1 conditional spec + uses 3 slash commands + reads logs from phone. All work.

---

## Cross-cutting: backend wire additions

These ship as needed alongside per-version client features. PC dispatch + Mac PM shim share the additions.

| Wire field | Added in version | Purpose |
|---|---|---|
| `kind: text \| spec \| image \| refine_request \| refine_response \| voice_turn` | v2.0 | base typing |
| `kind: heartbeat \| review_request \| review_decision \| suggest \| agent_status \| chain_spec` | v2.2/v2.3/v2.4/v2.6 | progressive |
| `attachment_url`, `attachment_preview` | v2.0 | image attach |
| `topic` (string tag) | v2.2 | mute by topic |
| `awaiting_decision` (bool) | v2.2 | decisions rail |
| `refine_id` (uuid) | v2.0 | refine round-trip match |
| `chain` (string[]) | v2.6 | round-trip specs |
| `condition` (struct) | v2.6 | conditional dispatch |

All additions are optional + back-compat. Older clients ignore unknown fields.

---

## Effort summary

| Version | iOS | PC | Mac shim | Total | Ships when |
|---|---|---|---|---|---|
| v2.0 LOCKED | 15-17h | 5-6h | 3h | ~25h | Started 2026-06-07 |
| v2.1 Spec Studio | 16h | 2h | 0 | 18h | After v2.0 |
| v2.2 Cockpit | 12h | 6h | 2h | 20h | After v2.1 |
| v2.3 Ship from phone | 13h | 6h | 1h | 20h | After v2.2 |
| v2.4 AI co-author | 10h | 3h | 1h | 14h | After v2.3 |
| v2.5 Ambient input | 18h | 0 | 0 | 18h | Parallel with v2.4 (iOS-only) |
| v2.6 Meta-orchestration | 16h | 8h | 4h | 28h | After v2.4 |
| **Total** | **100-102h iOS** | **30h PC** | **11h Mac shim** | **~143h** | |

At one full overnight per version (8h), 7 nights. Realistic with interleaved daytime debugging: 3 weeks calendar.

---

## What to ship first if you only want a subset

If "v2.0 + top-5", fold these into v2.0 as a stretch (additional ~16h):

- #4 Spec templates (2h) — biggest friction reduction
- #9 Inline diff review (5h) — closes review-on-phone loop  
- #2 All-systems dashboard (3h+2h+1h = 6h) — kills "is it broken" mental tax
- #5 Photo-to-spec (3h+1h = 4h) — unlocks "see this bug" specs
- #15 Smart autocomplete (4h+2h+1h = 7h) — 5× faster spec writing

Total v2.0+ = ~50h. Ships in 1 week if dedicated.

---

## Open questions

1. **Order:** ship strict v2.0 → v2.1 → … OR fold top-5 into v2.0 mega-ship?
2. **Watch app (v2.5):** include or skip? It's a separate WatchOS target with its own complexity.
3. **CarPlay (v2.5):** include or skip? Apple review for CarPlay is its own multi-week saga.
4. **Memory inspector (v2.4) edit:** allow CEO to edit PM/SWE memory directly, or read-only?

Tell me your call on those 4 and the order, and I'll dispatch the ship plan.
