import AppKit
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
            Button("Edit Pronunciations…") { Pronunciations.openInEditor() }
        }
    }
}

enum Pronunciations {
    static var fileURL: URL {
        let support = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Application Support/Susurro/pronunciations.json")
        return support
    }

    static func openInEditor() {
        ensureFileExists()
        NSWorkspace.shared.open(fileURL)
    }

    private static func ensureFileExists() {
        let url = fileURL
        if FileManager.default.fileExists(atPath: url.path) { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let template = """
        {
          "es": {
            "dónde": "<emphasis level=\\"moderate\\">dónde</emphasis>"
          },
          "en": {}
        }
        """
        try? template.write(to: url, atomically: true, encoding: .utf8)
    }
}
