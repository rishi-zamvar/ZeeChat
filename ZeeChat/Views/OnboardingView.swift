import SwiftUI

/// First-launch sheet — system-boot sequence aesthetic. Lines type out
/// one-by-one with a blinking caret. Final "GET STARTED" hands off to
/// Settings for token entry.
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var visibleLines: Int = 0
    @State private var ready: Bool = false

    private let lines: [BootLine] = [
        BootLine(prefix: "$",  body: "zeechat --init",            color: .outbound),
        BootLine(prefix: "..", body: "loading runtime",            color: .textDim),
        BootLine(prefix: "..", body: "probing tailnet",            color: .textDim),
        BootLine(prefix: "ok", body: "tailnet detected",           color: .macAccent),
        BootLine(prefix: "ok", body: "node: mac-claude@pm",        color: .macAccent),
        BootLine(prefix: "ok", body: "node: pc-claude@swe",        color: .pcAccent),
        BootLine(prefix: "..", body: "checking chat tokens",       color: .textDim),
        BootLine(prefix: "?",  body: "chat_token: NOT CONFIGURED", color: .outbound),
        BootLine(prefix: ">",  body: "tap GET STARTED to configure", color: .textPrimary),
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            DotGrid().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                    .padding(.bottom, 6)
                ForEach(lines.indices, id: \.self) { i in
                    if i < visibleLines {
                        BootLineView(line: lines[i])
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                if visibleLines == lines.count {
                    HStack(spacing: 8) {
                        Text(">")
                            .font(Theme.mono(15, weight: .bold))
                            .foregroundStyle(Theme.outbound)
                        BlinkingCaret(color: Theme.outbound)
                        Spacer()
                    }
                }
                Spacer()
                if ready {
                    Button(action: {
                        UserDefaults.standard.set(true, forKey: "zeechat.seenOnboarding")
                        onDone()
                    }) {
                        HStack(spacing: 8) {
                            Spacer()
                            Text("[GET STARTED]")
                                .font(Theme.mono(13, weight: .bold))
                                .tracking(1.5)
                            Spacer()
                        }
                        .foregroundStyle(Theme.bg)
                        .padding(.vertical, 14)
                        .background(Theme.outbound)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 22)
        }
        .preferredColorScheme(.dark)
        .onAppear { revealLines() }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle().fill(Theme.outbound).frame(width: 4, height: 18)
                Text("ZEECHAT")
                    .font(Theme.mono(20, weight: .bold))
                    .tracking(4.0)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("// secure tailnet chat with your two Claude instances")
                .font(Theme.mono(10))
                .tracking(0.3)
                .foregroundStyle(Theme.textGhost)
        }
    }

    private func revealLines() {
        Task { @MainActor in
            for i in 0..<lines.count {
                try? await Task.sleep(nanoseconds: 320_000_000)
                withAnimation(.easeOut(duration: 0.2)) {
                    visibleLines = i + 1
                }
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                ready = true
            }
        }
    }
}

private struct BootLine: Identifiable {
    let id = UUID()
    let prefix: String
    let body: String
    let color: BootColor
}

private enum BootColor {
    case outbound, textDim, macAccent, pcAccent, textPrimary
    var color: Color {
        switch self {
        case .outbound:    return Theme.outbound
        case .textDim:     return Theme.textDim
        case .macAccent:   return Theme.macAccent
        case .pcAccent:    return Theme.pcAccent
        case .textPrimary: return Theme.textPrimary
        }
    }
}

private struct BootLineView: View {
    let line: BootLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.prefix)
                .font(Theme.mono(12, weight: .bold))
                .foregroundStyle(line.color.color)
                .frame(width: 22, alignment: .leading)
            Text(line.body)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }
}
