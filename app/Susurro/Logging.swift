import os

enum AppLogger {
    static let subsystem = "com.benatespina.susurro"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let backend = Logger(subsystem: subsystem, category: "backend")
    static let selection = Logger(subsystem: subsystem, category: "selection")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
}
