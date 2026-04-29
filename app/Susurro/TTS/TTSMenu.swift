import SwiftUI

struct TTSMenu: View {
    @Bindable var settings: TTSSettings
    let onApply: () -> Void

    var body: some View {
        Menu("TTS Provider: \(settings.provider.displayName)") {
            ForEach(TTSProvider.allCases, id: \.self) { p in
                Button {
                    if p == .azure && !settings.azureConfigured {
                        TTSConfigWindowController.show(settings: settings) {
                            settings.provider = .azure
                            onApply()
                        }
                    } else {
                        settings.provider = p
                        onApply()
                    }
                } label: {
                    HStack {
                        if settings.provider == p { Image(systemName: "checkmark") }
                        Text(p.displayName)
                    }
                }
            }
            Divider()
            Button("Configure Azure…") {
                TTSConfigWindowController.show(settings: settings) {
                    if settings.provider == .azure { onApply() }
                }
            }
        }
    }
}
