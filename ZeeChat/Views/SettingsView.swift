import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var probe: ProbeResult? = nil
    @State private var probing = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ConversationBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    section(title: "CHAT TOKENS") {
                        Text("Each daemon issues its own chat_token. Generate via `gen_secrets.py --chat-only` on the host, paste below. PC is primary; Mac is optional.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textGhost)
                            .padding(.bottom, 4)
                        tokenField(label: "pc_chat_token", color: Theme.pcAccent,
                                   text: $settings.pcChatToken)
                        tokenField(label: "mac_chat_token", color: Theme.macAccent,
                                   text: $settings.macChatToken)
                    }
                    section(title: "PC DAEMON") {
                        terminalField(label: "host", text: $settings.pcHost)
                        terminalIntField(label: "port", value: $settings.pcPort)
                    }
                    section(title: "MAC DAEMON") {
                        terminalField(label: "host", text: $settings.macHost)
                        terminalIntField(label: "port", value: $settings.macPort)
                    }
                    section(title: "OBSERVER (DIAGNOSTIC)") {
                        terminalField(label: "host", text: $settings.observerHost)
                        terminalIntField(label: "port", value: $settings.observerPort)
                        SecureField("", text: $settings.observerToken)
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(10)
                            .background(Theme.surface)
                            .overlay(Rectangle().stroke(Theme.stroke, lineWidth: 1))
                    }
                    section(title: "CONNECTION TEST") {
                        Button { Task { await runProbe() } } label: {
                            HStack {
                                Text(probing ? "[PROBING…]" : "[RUN PROBE]")
                                    .font(Theme.mono(12, weight: .bold))
                                    .tracking(1.0)
                                Spacer()
                                if probing {
                                    ProgressView()
                                        .tint(Theme.bg)
                                }
                            }
                            .foregroundStyle(Theme.bg)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(settings.isConfigured ? Theme.outbound : Theme.surface)
                        }
                        .disabled(probing || !settings.isConfigured)

                        if let p = probe {
                            probeRow(label: "mac /api/v1/chat/inbox", outcome: p.mac)
                            probeRow(label: "pc  /api/v1/chat/inbox", outcome: p.pc)
                            probeRow(label: "observer",                outcome: p.observer)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CONFIG")
                    .font(Theme.mono(13, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(Theme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("DONE") { dismiss() }
                    .font(Theme.mono(12, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(settings.isConfigured ? Theme.outbound : Theme.textGhost)
                    .disabled(!settings.isConfigured)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("$")
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.outbound)
                Text("zeechat config")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("// tokens persist in iOS Keychain")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textGhost)
        }
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Rectangle().fill(Theme.outbound).frame(width: 3, height: 12)
                Text(title)
                    .font(Theme.mono(11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textPrimary)
            }
            content()
        }
    }

    private func tokenField(label: String, color: Color, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.mono(10, weight: .medium))
                .foregroundStyle(color)
            SecureField("", text: text)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.textPrimary)
                .tint(color)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.surface)
                .overlay(Rectangle().stroke(color.opacity(0.55), lineWidth: 1))
        }
    }

    private func terminalField(label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(width: 60, alignment: .leading)
            TextField("", text: text)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.outbound)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(Theme.surface)
        .overlay(Rectangle().stroke(Theme.stroke, lineWidth: 1))
    }

    private func terminalIntField(label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .frame(width: 60, alignment: .leading)
            TextField("", value: value, format: .number.grouping(.never))
                .font(Theme.mono(13))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.outbound)
                .keyboardType(.numberPad)
        }
        .padding(10)
        .background(Theme.surface)
        .overlay(Rectangle().stroke(Theme.stroke, lineWidth: 1))
    }

    private func runProbe() async {
        probing = true
        defer { probing = false }
        let client = DispatchClient(settings: settings)
        probe = await client.probe()
    }

    private func probeRow(label: String, outcome: ProbeOutcome) -> some View {
        HStack(spacing: 8) {
            StatusPill(label: outcome.isOk ? "OK" : "FAIL",
                       color: outcome.isOk ? Theme.macAccent : Theme.outbound)
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(outcome.detail)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textGhost)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface.opacity(0.6))
    }
}
