# ZeeChat v2.0 — Conversation Studio

Date: 2026-06-07
Status: DRAFT — pending CEO approval before shipping
Author: PM (Mac)

## Why

Current ZeeChat is a "Tailnet Terminal" aesthetic — monospace SF Mono, hard
2pt corners, dot-grid background, [SEEN]-style square-bracket pills, per-
contact saturated cyan/magenta bubble strokes. CEO: too jagged + UI hard
to use + needs to match Claude-app's calmer affordance + needs voice input
+ needs a spec-composer for staging requests to PM/SWE.

## Three things this ships

1. **Visual refresh** — softer, Claude-app aligned
2. **Spec composer** — staging area for multi-turn request composition before dispatch
3. **Multimodal input** — voice dictation + image attach (voice-call mode deferred to v2.1)

## Out of scope (defer)

- v2.1: voice-call mode (Claude responds as audio, not text)
- v2.1: file attachments beyond images (PDFs, MD docs)
- v2.2: rich preview of dispatched specs (inline diff / tree view)
- v2.2: per-chat search

---

## 1. Visual refresh

| | Before (Tailnet Terminal) | After (v2.0 Conversation Studio) |
|---|---|---|
| **Corner radius** | 2pt (near-hard) | 18pt outer / 14pt inner |
| **Typography** | SF Mono everywhere | SF Pro Text body + SF Pro Display titles; SF Mono ONLY for code blocks + commands |
| **Background** | `#0A0A0F` blue-cast + DotGrid | `#1A1A1E` neutral warm-black + subtle vertical gradient lightening toward top |
| **Inbound bubble** | Bright surface + cyan/magenta 1pt border | Brighter card surface, no border, 4pt left edge in **desaturated** per-contact accent |
| **Outbound bubble** | Amber background, hard edges | Neutral surface with subtle gradient, soft shadow, no border |
| **Status pills** | `[SEEN]` square-bracket monospace | Rounded capsules, lowercase, dim text "seen 2:47p" |
| **Speaker glyph** | `>` / `<` ASCII prefix | Removed — accent edge bar is the speaker signal |
| **Per-contact accent** | Saturated (full-strength cyan/magenta) | Desaturated 50%, used only as 4pt edge bar + small dot in toolbar |

Keep:
- Per-contact identity (Mac PM vs PC SWE) — distinct hue still present, just calmer
- Receipt states (sent / delivered / seen)
- Dark mode only (no light mode this ship)

## 2. Spec composer

Tap the **Spec** button (new, above composer, below messages):

```
┌─────────────────────────────────────┐
│  SPEC                          [×]  │
├─────────────────────────────────────┤
│  Target:  [ PM ] [ SWE ] [ BOTH ]   │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ I want to fix the streak    │    │
│  │ panel to show kcal this     │    │
│  │ week as a fourth metric…    │    │
│  │                             │    │
│  │                       (mic) │    │
│  └─────────────────────────────┘    │
│                                     │
│  [ Refine ]  [ Save draft ]         │
│                                     │
│  [    Send spec to PM    ]          │
└─────────────────────────────────────┘
```

- **Target chips**: PM (Mac), SWE (PC), or BOTH. Defaults to BOTH (matches CLAUDE.md's `dispatch_to_team target='all'` default).
- **Big text field**: spec body. Voice dictation via Apple Speech API in-place.
- **Refine button**: optional — sends current draft + "rewrite this as a clearer dev spec" prompt to Claude (via the existing dispatch /api/v1/chat shim, same as a normal chat). Returns expanded version into the field. CEO can edit, refine again, or send.
- **Save draft**: persists locally, accessible from a new "Specs" tab. Drafts survive app kill.
- **Send spec to X**: dispatches the body via existing message bus, with `kind: "spec"` metadata. Recipient (PM/SWE) sees it tagged as `SPEC:` in their inbox + renders with monospace + line numbers for easier execution.

Open question for CEO: does Refine call the same Claude account/key the WC + CH apps use, or its own? Default: shared key, audited via existing audit_log path.

## 3. Multimodal input

**Voice**:
- Mic button in main composer + in spec composer
- Long-press to record, release to transcribe
- Apple `SFSpeechRecognizer` — on-device on iOS 17+
- Transcribed text drops into the active text field (composer or spec body)
- No "voice message" sending — voice = dictation only this ship

**Image**:
- Paperclip icon in composer
- Camera / photo library / files picker
- Image attached as a message of `kind: "image"`
- Backend: ZeeCloud-mounted dispatch service stores under `~/.dispatch/attachments/<msg_id>/<filename>` + serves via Tailscale-internal URL; message body carries the URL + a small preview thumbnail (JPEG, max 300px)
- PM/SWE renders inline preview in their dispatch read view

Voice-call mode (talk + Claude voice-back) — defer to v2.1.

## 4. Compact chat mode

Toolbar toggle (icon = `text.alignleft` for compact, `text.alignleft.fill` for expanded).

| Compact | Expanded (today) |
|---|---|
| One line per message, ellipsis if > 60 chars | Full bubble with header |
| No timestamp inline | Timestamp on tap-hold |
| No accent edge bar | Accent edge bar |
| 36pt row height | Variable |
| Tap row → expanded for that one message | All visible |

State persists per-chat. Default: expanded on first install, sticky after.

## 5. Backend changes

Minimal — keeps the existing dispatch wire stable:

```
DispatchMessage {
  ...
  kind: "text" | "spec" | "image"   // NEW, optional, default "text"
  attachment_url: str | None        // NEW, present only when kind=image
  attachment_preview: str | None    // NEW, base64 JPEG <=300px
}
```

Backend (PC dispatch + Mac PM shim) accepts these fields, persists them, replays on inbox/read. The PM Mac shim has been deferred per memory (`project_zeechat.md` notes v1.2 WIP drift); this ship picks it up + ships v2.0 simultaneously.

## 6. Implementation slices

iOS (Mac PM owns, since this is iOS code on Mac):
- (a) Theme.swift rewrite — soft palette, 18pt radius, SF Pro body, gradient bg
- (b) ChatView visual pass — new BubbleShape, edge bar, capsule pills
- (c) Compact mode toggle + view variant
- (d) Voice composer — SFSpeechRecognizer plumbing + mic button + permission flow
- (e) Image attach — UIImagePickerController + payload encoding
- (f) Spec composer — modal sheet + Refine call + Draft persistence + target chips
- (g) `kind` field plumbing through DispatchMessage encoder/decoder
- (h) Snapshot tests for new theme + spec composer

PC dispatch (SWE owns):
- (i) Accept + persist + serve new fields
- (j) Attachment storage path + Tailscale-internal serving
- (k) Replay-safe migration for existing messages (kind defaults to "text")

Mac PM dispatch shim (PM owns):
- (l) Mirror PC's field acceptance (already deferred, this is the moment to pick up)

## 7. Tests + acceptance

- Theme snapshot tests (light vs current dark — dark only this ship)
- Spec composer: draft persistence across app kill
- Voice: end-to-end transcription on a 5s test phrase
- Image attach: encode + decode round-trip, preview thumbnail integrity
- Wire: `kind=spec` message round-trips with body intact
- Wire: `kind=image` message round-trips with attachment URL retrievable

CEO acceptance gate:
- 5-min visual review on phone — softness reads as intended
- Send 1 spec end-to-end PM + SWE — confirms wire works
- Record 1 voice dictation in main chat — confirms transcription latency feels right
- Attach 1 image — confirms preview shows on PM side

## 8. Open questions (decide before exec)

1. **Refine prompt source**: shared Claude key or own?
   → Recommend shared (reuse existing audit, no new secret to rotate)
2. **Spec drafts location**: device-only or sync to ZeeCloud?
   → Recommend device-only this ship (cross-device sync = v2.1)
3. **Voice-call mode**: defer or include?
   → Recommend defer (complex enough for its own ship)
4. **Compact mode default for existing users**: keep expanded or default compact?
   → Recommend expanded (no surprise on upgrade)

---

## Ship plan

ETA estimate: 6-8 hours iOS work (Mac PM) + 2-3 hours PC dispatch (SWE).
Lands as ZeeChat v2.0.0, sequential PR pattern (no feature branch).
