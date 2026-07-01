import SwiftUI

/// ZeeChat v2.0 design tokens — "Conversation Studio" aesthetic.
///
/// Direction: warm minimal, Claude-app aligned. SF Pro body, 18pt outer /
/// 14pt inner radius, neutral warm-black background with subtle gradient
/// lightening toward the top. Per-contact accent desaturated 50% as a
/// 4pt left-edge bar on inbound bubbles (not a saturated border). No
/// terminal glyphs, no dot grid, no bracket-pills.
///
/// Replaces v1.3 "Tailnet Terminal" (monospace SF Mono everywhere, hard
/// 2pt corners, [BRACKETED] pills, saturated cyan/magenta strokes,
/// DotGrid canvas). Snapshot baselines locked at first install of v2.0.
enum Theme {

    // MARK: - Color tokens (Conversation Studio palette)

    /// Neutral warm-black base. No blue cast (v1.3's `#0A0A0F` read cold).
    /// Slight warm tint reads as "comfortable dark" not "phosphor monitor".
    static let bg          = Color(red: 0.102, green: 0.102, blue: 0.118)   // #1A1A1E
    /// Card surface for outbound bubbles. Lifted from bg for hierarchy
    /// without aggressive contrast.
    static let surface     = Color(red: 0.137, green: 0.137, blue: 0.157)   // #232328
    /// Slightly brighter surface for inbound bubbles + active states.
    static let surfaceHi   = Color(red: 0.176, green: 0.176, blue: 0.200)   // #2D2D33
    /// Subtle divider strokes (separators, very thin lines on cards).
    static let stroke      = Color(red: 0.235, green: 0.235, blue: 0.267)   // #3C3C44

    static let textPrimary = Color(red: 0.953, green: 0.957, blue: 0.969)   // #F3F4F7
    static let textDim     = Color(red: 0.647, green: 0.659, blue: 0.706)   // #A5A8B4
    static let textGhost   = Color(red: 0.420, green: 0.427, blue: 0.475)   // #6B6D79

    /// Outbound accent — warm but desaturated. Used sparingly (send button,
    /// active states). NOT the bubble fill (v1.3 was loud amber-on-dark).
    static let outbound    = Color(red: 0.984, green: 0.776, blue: 0.514)   // #FBC683

    /// Per-contact accent — DESATURATED 50% vs v1.3. Used as a 4pt left
    /// edge bar on inbound bubbles + small dot in toolbar. Never as full
    /// bubble fill or saturated border (those reads as "alert", not as
    /// "this is mac vs pc").
    static let macAccent   = Color(red: 0.580, green: 0.776, blue: 0.847)   // #94C6D8 (was loud cyan)
    static let pcAccent    = Color(red: 0.847, green: 0.580, blue: 0.722)   // #D894B8 (was loud magenta)

    /// Status colors for receipt state. Subdued — they live in a small
    /// capsule pill, not as a glaring color block.
    static let stateSeen      = outbound
    static let stateDelivered = textDim
    static let stateSent      = textGhost

    /// Per-contact accent — single source of truth so bubbles, headers,
    /// avatars, online dots, and edge bars all tint consistently.
    static func accent(for role: ContactRole) -> Color {
        switch role {
        case .pm:  return macAccent
        case .swe: return pcAccent
        }
    }

    // MARK: - Typography

    /// Body font: SF Pro Text. Readable, not screaming "terminal".
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Display font: SF Pro Display, slightly heavier for titles + labels.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Mono ONLY for code blocks + inline commands. Not for chrome.
    /// Reserved use keeps the terminal aesthetic out of conversational
    /// surfaces while preserving it for technical content.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Sizes

    /// Outer bubble radius — soft. v1.3 was 2pt (near-hard terminal).
    static let bubbleRadius: CGFloat = 18
    /// Inner content radius — slightly tighter than outer for the
    /// gradient + edge-bar composition to read cleanly.
    static let bubbleInnerRadius: CGFloat = 14
    static let bubblePadH: CGFloat    = 14
    static let bubblePadV: CGFloat    = 12
    /// Left edge bar width for inbound bubbles (the desaturated accent
    /// strip that signals speaker identity instead of a border).
    static let edgeBarWidth: CGFloat = 4
}

// MARK: - Backdrop gradient

/// Subtle vertical gradient lightening toward the top — replaces v1.3's
/// DotGrid Canvas. Reads as "ambient depth", not "tech mesh".
struct ConversationBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.137, green: 0.137, blue: 0.157),  // bg lightened ~5%
                Theme.bg,
                Theme.bg,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Bubble shape

/// Soft, uniformly-rounded conversation card — `Theme.bubbleRadius` on
/// every corner with continuous curvature. Reads as a calm chat bubble,
/// not a terminal window. Speaker identity is conveyed by fill color and
/// the inbound accent edge bar, not by corner geometry.
struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: Theme.bubbleRadius, height: Theme.bubbleRadius),
            style: .continuous
        )
        return p
    }
}

// MARK: - Accent edge bar (replaces saturated border)

/// 4pt left edge bar in desaturated per-contact accent. Used on inbound
/// bubbles to signal speaker identity without the loud border treatment
/// of v1.3. Stacks behind the bubble in a ZStack(alignment: .leading).
struct AccentEdgeBar: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: Theme.edgeBarWidth)
    }
}

// MARK: - Capsule status pill (replaces [BRACKETED])

/// Lowercase rounded capsule for receipt state. Replaces v1.3's
/// `[SEEN]` / `[DELIVERED]` / `[SENT]` bracket pills.
struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label.lowercased())
            .font(Theme.body(11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Composer caret (still useful, softer color now)

struct BlinkingCaret: View {
    @State private var visible = true
    var color: Color = Theme.outbound

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
            }
    }
}
