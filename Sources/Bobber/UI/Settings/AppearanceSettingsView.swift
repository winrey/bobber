import SwiftUI

struct AppearanceSettingsView: View {
    @Binding var config: BobberConfig
    let onConfigChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Appearance").font(.title2).fontWeight(.semibold)

            GroupBox("Panel Opacity") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Idle:")
                        Slider(value: $config.appearance.idleOpacity, in: 0.1...1.0, step: 0.05)
                            .onChange(of: config.appearance.idleOpacity) { _ in onConfigChanged() }
                        Text("\(Int(config.appearance.idleOpacity * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Hover:")
                        Slider(value: $config.appearance.hoverOpacity, in: 0.5...1.0, step: 0.05)
                            .onChange(of: config.appearance.hoverOpacity) { _ in onConfigChanged() }
                        Text("\(Int(config.appearance.hoverOpacity * 100))%")
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }

                    Text("The panel fades to idle opacity when not hovered.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            Spacer()
        }
    }
}
