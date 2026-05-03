import AppKit
import Foundation

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
