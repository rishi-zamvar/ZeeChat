# ZeeChat

A private iOS chat client for talking to your two Claude coding agents —
**Mac Claude (`pm`)** and **PC Claude (`swe`)** — over a Tailscale
network. Messages travel through each machine's dispatch daemon via its
iPhone-facing `/api/v1/chat/*` shim; nothing leaves the tailnet.

This is the **v2.0 "Conversation Studio"** line: a visual refresh plus
the foundations for spec composing, voice dictation / voice-call mode,
and image attach. See `design/v2/SPEC-LOCKED.md` and
`design/v2/ROADMAP.md` for product scope and the version arc.

## Requirements

- Xcode 15+ (SDK targets iOS 17.0)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — the Xcode project
  is generated from `project.yml`, not committed (`ZeeChat.xcodeproj/`
  is git-ignored)

```sh
brew install xcodegen
```

## Build, run, test

```sh
# Generate ZeeChat.xcodeproj from project.yml (re-run after adding files)
xcodegen generate

# Run the unit tests on a simulator
xcodebuild \
  -project ZeeChat.xcodeproj \
  -scheme ZeeChat \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

Open `ZeeChat.xcodeproj` in Xcode to run the app on a simulator or
device. The same build + test flow runs in CI on every PR to `main`
(`.github/workflows/test.yml`).

The unit suite is intentionally offline and deterministic — no network,
secrets, or live daemon — so it runs cleanly anywhere. The tests cover
the wire model, timestamp/checksum/id utilities, the local `DraftStore`,
the async `RefineCoordinator`, and the `AttachmentClient` image pipeline.

## Configuration

Each daemon issues its own `chat_token` (generated host-side, e.g.
`gen_secrets.py --chat-only`). Enter tokens in the in-app **Config**
screen; they persist to the iOS Keychain (`Keychain.swift`), while
non-secret host/port values live in `UserDefaults` (`AppSettings.swift`).
PC (`swe`) is the primary path; the Mac (`pm`) shim is optional and lands
later.

For simulator verification, tokens and demo state can be seeded via
environment variables (see `AppSettings.init` and `ChatStore.init`):

| Variable | Effect |
| --- | --- |
| `ZEECHAT_PC_CHAT_TOKEN` / `ZEECHAT_MAC_CHAT_TOKEN` | Seed a chat token (also persisted to Keychain) |
| `ZEECHAT_PEER_TOKEN` / `ZEECHAT_OBSERVER_TOKEN` | Seed legacy peer / observer tokens |
| `ZEECHAT_SEED_DEMO=1` | Populate demo threads for screenshots |
| `ZEECHAT_OPEN_CONTACT=pm\|swe` | Auto-navigate to a thread on launch |

## Architecture

SwiftUI app, MVVM-ish, with a thin service layer. Source lives under
`ZeeChat/`:

- **`Models/`** — `DispatchMessage` (the on-wire shape mirroring the
  daemon's `Message`), `AppSettings`, and the `SHA256` / `Checksum` /
  `ISO8601` / `DispatchID` helpers.
- **`Networking/`** — `DispatchClient` (send / inbox / health-probe
  against the chat shim) and `ChatStore`, the `@MainActor` view model
  that owns per-contact threads, the polling loop, unread counts, read
  receipts, and the "thinking" heuristic.
- **`Storage/`** — `ThreadStore` (atomic per-contact thread persistence)
  and `Keychain`.
- **`Services/`** — `NotificationService`, `BackgroundRefresh`
  (BGAppRefreshTask), `RefineCoordinator` (async refine round-trip
  matcher), `DraftStore` (local-first spec persistence), `AttachmentClient`
  (image encode + thumbnail + sha), the voice `VoiceRecognizer` /
  `SpeechSynthesizer`, and `SpecDispatcherImpl`.
- **`Views/`** — `ContactsView`, `ChatView`, `SettingsView`,
  `OnboardingView`, and the v2.0 composer surfaces (`SpecComposerView`,
  `SpecLibraryView`, `VoiceCallView`).
- **`Design/`** — the `Theme` design tokens and shared shapes.

### Forward-compatible wire

`DispatchMessage` already carries the v2.0 additive fields (`kind`,
`attachment_url`, `attachment_preview`, `attachment_sha256`, `refine_id`)
as **optionals**, so the client decodes cleanly whether or not the
backend has shipped them yet. Until the daemon populates those fields,
higher layers thread markers (`[KIND:…]`, `[RID:…]`, `[SPEC]`, `[PHOTO]`,
`[VOICE]`) through the message body — see `ChatStore.sendRaw` and
`SpecDispatcherImpl`. When the backend lands the real schema, swap those
seams to forward the structured fields; no decode change is needed.
```
