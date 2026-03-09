import SwiftUI

struct SoundsSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void
    let soundManager: SoundManager

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

            GroupBox(label: Text("Sound Effects")) {
                VStack(alignment: .leading, spacing: 10) {
                    soundPickerRow(label: "Permission:", selection: $config.sounds.permissionSound)
                    soundPickerRow(label: "Completion:", selection: $config.sounds.completionSound)
                    soundPickerRow(label: "Decision:", selection: $config.sounds.decisionSound)
                }
                .padding(8)
            }
            .disabled(!config.sounds.enabled)

            Spacer()
        }
    }

    private func soundPickerRow(label: String, selection: Binding<String>) -> some View {
        HStack {
            Text(label)
                .frame(width: 90, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(SoundManager.availableSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(width: 130)
            .onChange(of: selection.wrappedValue) { _ in onConfigChanged() }
            Button {
                soundManager.preview(soundName: selection.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}