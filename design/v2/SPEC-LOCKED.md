# ZeeChat v2.0 — Conversation Studio (LOCKED)

Date: 2026-06-07
Status: LOCKED per CEO sign-off — ready to ship
Supersedes: SPEC.md (draft)

## Locked decisions (CEO 2026-06-07)

1. **Refine = dispatch round-trip through PM/SWE Claude session** (not direct
   Anthropic API). Same daemon already in use. CEO's Claude Code
   subscription pays. Target chip selects which Claude session refines.
2. **Spec drafts sync to ZeeCloud** (not device-only).
3. **Voice-call mode INCLUDED this ship** — full back-and-forth audio with
   STT + TTS + interrupt handling.
4. **Compact mode default = expanded** on upgrade; sticky per-chat after toggle.

## Updated ship scope

iOS (~15-17h):
- Visual refresh (Theme rewrite, bubble + composer + pills)
- Compact mode toggle + view variant
- Spec composer (sheet + chips + Refine round-trip handling)
- Voice dictation (SFSpeechRecognizer in composer + spec)
- **Voice-call mode** (continuous STT + AVSpeechSynthesizer TTS + voice activity detection + interrupt)
- Image attach (UIImagePickerController + payload encoding)
- ZeeCloud draft sync (push/pull endpoints + reconcile)
- DispatchMessage `kind` + `attachment_url` + `attachment_preview` plumbing
- Snapshot + unit tests

PC dispatch (~5-6h, SWE):
- Accept + persist + serve new `kind` / attachment fields
- Attachment storage path + Tailscale-internal serving
- ZeeCloud draft endpoints (POST /drafts, GET /drafts, DELETE /drafts/{id})
- Replay-safe migration for existing messages
- **Refine handler**: when SWE dispatch receives `kind="refine"`, it reads
  the body, sends to SWE Claude session as a special-prefixed message, gets
  the refined text back, dispatches a `kind="refine_response"` reply

Mac PM shim (~3h, PM):
- Mirror PC's field acceptance
- Mac PM's own Refine handler (since CEO can target PM chip)
- Was deferred per `project_zeechat.md`; this is the moment

## Refine round-trip wire

```
1. iOS user types "fix the streak panel" in spec composer.
2. iOS user taps Refine, target=PM.
3. iOS sends DispatchMessage{
     to: "pm", kind: "refine_request", body: "<draft text>",
     refine_id: "<uuid>"
   }
4. Mac PM dispatch receives. PM Claude session sees kind=refine_request,
   processes via the prompt "Expand this user request into a clearer dev
   spec, preserving intent. 200 words max. Return ONLY the refined text."
5. PM Claude dispatches DispatchMessage{
     to: "ceo", kind: "refine_response", body: "<refined>",
     refine_id: "<same uuid>"
   }
6. iOS receives refine_response, matches by refine_id, drops body into
   the active spec composer field.
7. CEO edits / refines again / sends as kind="spec".
```

Refine round-trip is async — UX shows a "refining…" pulse on the composer
+ a 30s timeout. Multiple in-flight refines disambiguated by refine_id.

## Voice-call mode

**Trigger**: separate icon in composer (phone glyph). Tap to start, tap to end.

**Pipeline**:
1. Activate `AVAudioSession` for `playAndRecord` + `defaultToSpeaker`
2. Start `SFSpeechRecognizer` continuous task
3. Voice activity detection (VAD): when 1.5s of silence after transcribed text,
   flush as a "user turn"
4. Send the turn as DispatchMessage{ kind: "voice_turn", body: "<transcribed>" }
5. Mac PM / PC SWE responds normally; iOS receives the response
6. Speak the response via `AVSpeechSynthesizer` (en-US, premium voice if
   available, fall back to compact)
7. While speaking, user tap-to-interrupt stops TTS mid-sentence + reactivates STT

**Visual**: full-screen call modal — large waveform, contact accent, "tap to end",
transcribed text scrolls below as it's recognized.

## File scaffold (iOS)

```
ZeeChat/Design/Theme.swift               REWRITE — soft palette
ZeeChat/Design/Components/               NEW — Bubble, Pill, EdgeBar shared
ZeeChat/Views/ChatView.swift             REWRITE — soft visuals + compact toggle
ZeeChat/Views/SpecComposerView.swift     NEW — modal sheet, target chips, refine
ZeeChat/Views/VoiceCallView.swift        NEW — full-screen voice mode
ZeeChat/Services/VoiceRecognizer.swift   NEW — SFSpeech wrapper
ZeeChat/Services/SpeechSynthesizer.swift NEW — AVSpeech wrapper
ZeeChat/Services/DraftStore.swift        NEW — local + ZeeCloud sync
ZeeChat/Services/RefineCoordinator.swift NEW — refine round-trip matcher
ZeeChat/Models/DispatchMessage.swift     EXTEND — kind, attachment_url, _preview
ZeeChat/Networking/AttachmentClient.swift NEW — image upload + thumbnail
```

## Ship order (iOS)

P0 visual refresh + compact (CEO can SEE the change first):
  → Theme.swift + ChatView visuals + compact toggle → install → CEO eyeball

P1 spec composer + draft sync:
  → SpecComposerView + DraftStore + Refine round-trip + RefineCoordinator
  → Mac PM + PC SWE refine handlers landed in parallel
  → CEO sends 1 spec end-to-end

P2 multimodal:
  → Voice dictation (SFSpeechRecognizer wrapper)
  → Image attach (picker + payload encoding)
  → AttachmentClient + PC storage endpoints
  → CEO records a dictation + attaches an image

P3 voice-call:
  → AudioSession + continuous STT + VAD
  → SpeechSynthesizer wrapper
  → VoiceCallView modal
  → CEO has a 30s voice convo with PM Claude

Each P-band ships an installable build to CEO's phone for live eyeball.

## Test coverage

- Theme snapshot tests against soft baseline (PNG fixtures)
- DraftStore: persistence across app kill + ZeeCloud reconcile conflict resolution
- RefineCoordinator: refine_id matching, timeout, multiple in-flight
- VoiceRecognizer: 5s test phrase end-to-end
- SpeechSynthesizer: speak + interrupt mid-sentence
- AttachmentClient: encode/decode round-trip, thumbnail integrity
- Wire: kind=spec / refine_request / refine_response / voice_turn / image round-trips
