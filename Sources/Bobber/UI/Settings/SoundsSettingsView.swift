import SwiftUI

struct SoundsSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sounds").font(.title2).fontWeight(.semibold)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable sounds", isOn: $config.sounds.enabled)
                        .onChange(of: config.sounds.enabled) { _ in onConfigChanged() }

                    HStack {
                        Text("Volume:")
                        Slider(value: Binding(
                            get: { Double(config.sounds.volume) },
                            set: { config.sounds.volume = Float($0); onConfigChanged() }
                        ), in: 0...1, step: 0.05)
                        Text("\(Int(config.sounds.volume * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .disabled(!config.sounds.enabled)

                    HStack {
                        Text("Cooldown:")
                        TextField("", value: $config.sounds.cooldownSeconds, format: .number)
                            .frame(width: 60)
                            .onChange(of: config.sounds.cooldownSeconds) { _ in onConfigChanged() }
                        Text("seconds")
                            .foregroundColor(.secondary)
                    }
                    .disabled(!config.sounds.enabled)

                    Text("Minimum time between sounds to prevent spam.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            Spacer()
        }
    }
}
