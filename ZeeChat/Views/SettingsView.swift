import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var probe: ProbeResult? = nil
    @State private var probing = false

    var body: some View {
        Form {
            Section {
                Text("ZeeChat talks to the dispatch daemons over Tailscale. Paste the peer + observer tokens from `~/.dispatch/secrets.toml`.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Mac daemon (pm)") {
                LabeledTextField(label: "Host", text: $settings.macHost,
                                 autocaps: .never)
                LabeledIntField(label: "Port", value: $settings.macPort)
            }

            Section("PC daemon (swe)") {
                LabeledTextField(label: "Host", text: $settings.pcHost,
                                 autocaps: .never)
                LabeledIntField(label: "Port", value: $settings.pcPort)
            }

            Section("Observer (Mac)") {
                LabeledTextField(label: "Host", text: $settings.observerHost,
                                 autocaps: .never)
                LabeledIntField(label: "Port", value: $settings.observerPort)
            }

            Section("Tokens") {
                SecureField("peer_token", text: $settings.peerToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("observer.token", text: $settings.observerToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await runProbe() }
                } label: {
                    HStack {
                        Text(probing ? "Probing…" : "Test connection")
                        Spacer()
                        if probing { ProgressView() }
                    }
                }
                .disabled(probing || !settings.isConfigured)
                if let p = probe {
                    probeRow(label: "Mac /peer/ping", outcome: p.mac)
                    probeRow(label: "PC /peer/ping",  outcome: p.pc)
                    probeRow(label: "Observer",       outcome: p.observer)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .disabled(!settings.isConfigured)
            }
        }
    }

    private func runProbe() async {
        probing = true
        defer { probing = false }
        let client = DispatchClient(settings: settings)
        probe = await client.probe()
    }

    private func probeRow(label: String, outcome: ProbeOutcome) -> some View {
        HStack {
            Image(systemName: outcome.isOk ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(outcome.isOk ? .green : .red)
            Text(label)
            Spacer()
            Text(outcome.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var autocaps: TextInputAutocapitalization = .sentences

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            TextField(label, text: $text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(autocaps)
                .autocorrectionDisabled()
        }
    }
}

private struct LabeledIntField: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            TextField(label, value: $value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
        }
    }
}
