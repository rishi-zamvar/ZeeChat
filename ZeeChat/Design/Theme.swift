import SwiftUI

/// ZeeChat design tokens — "Tailnet Terminal" aesthetic.
///
/// Direction: tech-noir terminal, not cliché CRT-phosphor. Monospaced
/// everywhere, hard 90° corners, amber outbound vs per-contact tinted
/// inbound (cyan for Mac, magenta for PC) for instant recognition.
/// Background dot-grid echoes the app-icon's tailnet mesh motif.
enum Theme {

    // MARK: - Color tokens

    /// Near-void background. Slight blue cast to distinguish from pure
    /// system black — feels like a phosphor monitor in a dark room.
    static let bg          = Color(red: 0.039, green: 0.039, blue: 0.059)   // #0A0A0F
    static let surface     = Color(red: 0.078, green: 0.078, blue: 0.110)   // #14141C
    static let surfaceHi   = Color(red: 0.118, green: 0.118, blue: 0.157)   // #1E1E28
    static let stroke      = Color(red: 0.196, green: 0.196, blue: 0.255)   // #323241
    static let textPrimary = Color(red: 0.953, green: 0.957, blue: 0.969)   // #F3F4F7
    static let textDim     = Color(red: 0.529, green: 0.541, blue: 0.620)   // #87899E
    static let textGhost   = Color(red: 0.314, green: 0.318, blue: 0.396)   // #505165

    /// CEO outbound = warm amber phosphor. Reads as "your voice".
    static let outbound    = Color(red: 1.000, green: 0.722, blue: 0.420)   // #FFB86B

    /// Mac Claude inbound = cool cyan. Distinctly different from PC.
    static let macAccent   = Color(red: 0.478, green: 0.906, blue: 1.000)   // #7AE7FF
    /// PC Claude inbound = warm magenta. Distinctly different from Mac.
    static let pcAccent    = Color(red: 1.000, green: 0.478, blue: 0.714)   // #FF7AB6

    /// Status colors mapped to receipt state.
    static let stateSeen      = outbound
    static let stateDelivered = textDim
    static let stateSent      = textGhost

    /// Per-contact accent — single source of truth so bubbles, headers,
    /// avatars, online dots, and borders all tint consistently.
    static func accent(for role: ContactRole) -> Color {
        switch role {
        case .pm:  return macAccent
        case .swe: return pcAccent
        }
    }

    // MARK: - Typography

    /// Body font: SF Mono. Available on every iOS device without bundling.
    /// Using `.monospaced` design ensures it falls back gracefully.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Sizes

    static let messageRadius: CGFloat = 2   // Nearly hard 90° — terminal feel
    static let bubblePadH: CGFloat    = 12
    static let bubblePadV: CGFloat    = 10
}

// MARK: - Dot-grid background

/// Subtle dot grid echoing the app icon's tailnet mesh. Renders as a
/// Canvas so it stays cheap and stays crisp on any density. Apply via
/// `.background(DotGrid())` on root views.
struct DotGrid: View {
    var dotSpacing: CGFloat = 24
    var dotSize: CGFloat = 1.4
    var dotColor: Color = Theme.stroke.opacity(0.42)

    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / dotSpacing) + 1
            let rows = Int(size.height / dotSpacing) + 1
            for c in 0...cols {
                for r in 0...rows {
                    let x = CGFloat(c) * dotSpacing
                    let y = CGFloat(r) * dotSpacing
                    let rect = CGRect(x: x - dotSize / 2,
                                      y: y - dotSize / 2,
                                      width: dotSize, height: dotSize)
                    ctx.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Bubble shape

/// Hard-cornered bubble with a single asymmetric notch on the "tail"
/// side. Reads as a terminal window, not iMessage.
struct BubbleShape: Shape {
    let isFromMe: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = Theme.messageRadius
        // Standard rounded rect — tiny radius gives the near-hard feel.
        p.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: r, height: r),
            style: .continuous
        )
        return p
    }
}

// MARK: - Composer caret (blinking)

struct BlinkingCaret: View {
    @State private var visible = true
    var color: Color = Theme.outbound

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 8, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
            }
    }
}

// MARK: - Status pill (e.g. [SEEN])

struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 0) {
            Text("[")
                .foregroundStyle(Theme.textGhost)
            Text(label)
                .foregroundStyle(color)
            Text("]")
                .foregroundStyle(Theme.textGhost)
        }
        .font(Theme.mono(10, weight: .semibold))
        .tracking(0.5)
    }
}
