import Darwin
import Foundation
import os

enum BackendProcessError: Error, Sendable {
    case alreadyRunning(pid: Int32)
    case spawnFailed(String)
    case healthTimeout
    case noLockfile
}

actor BackendProcess {
    enum State: Sendable {
        case stopped
        case starting
        case ready(BackendClient)
        case restarting(attempt: Int)
        case crashed(reason: String)
    }

    private(set) var state: State = .stopped
    private var process: Process?
    private var stateContinuations: [AsyncStream<State>.Continuation] = []
    private var isStopping: Bool = false
    private var restartAttempts: Int = 0
    private var lastExtraEnv: [String: String] = [:]

    func start(extraEnv: [String: String] = [:]) async throws {
        switch state {
        case .starting, .ready:
            return
        case .stopped, .crashed, .restarting:
            break
        }

        if let existing = try? readLockfile() {
            if isPidAlive(existing.pid) {
                // The recorded PID is alive. Probe health with a short timeout to
                // distinguish a healthy backend we can adopt from an orphan that is
                // still occupying the port but not serving requests.
                let candidate = BackendClient(
                    lockfile: existing,
                    session: makeShortTimeoutSession(timeout: 0.5)
                )
                let isHealthy = (try? await candidate.health()) == .ready
                if isHealthy {
                    // Healthy leftover — adopt it, skip spawn entirely.
                    AppLogger.backend.info("adopted existing backend pid=\(existing.pid, privacy: .public) port=\(existing.port, privacy: .public)")
                    restartAttempts = 0
                    await setState(.ready(BackendClient(lockfile: existing)))
                    return
                } else {
                    // Orphan: alive but not serving. Kill it so we can bind the port.
                    kill(existing.pid, SIGTERM)
                    AppLogger.backend.info("recovered from stale lockfile, killed orphan PID \(existing.pid, privacy: .public)")
                    try? FileManager.default.removeItem(at: LockfileLocator.path)
                }
            } else {
                // PID is dead — stale lockfile. Clean it up so our fresh lockfile lands cleanly.
                try? FileManager.default.removeItem(at: LockfileLocator.path)
            }
        }

        await setState(.starting)

        let libDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let hfHome = libDir
            .appending(path: "Application Support/Susurro/models")
            .path

        let proc = Process()
        proc.executableURL = URL(filePath: "/Users/benatespina/Developer/susurro/backend/.venv/bin/python")
        proc.arguments = ["-m", "susurro_backend"]
        proc.currentDirectoryURL = URL(filePath: "/Users/benatespina/Developer/susurro/backend")
        var environment: [String: String] = [
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
            "HF_HOME": hfHome,
            "SUSURRO_TTS_PROVIDER": "edge",
        ]
        for (k, v) in extraEnv { environment[k] = v }
        lastExtraEnv = extraEnv
        proc.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        proc.terminationHandler = { [weak self] _ in
            Task { [weak self] in
                await self?.handleTermination()
            }
        }

        Task {
            for await line in lines(from: stdoutPipe) {
                AppLogger.backend.info("\(line, privacy: .public)")
            }
        }

        Task {
            for await line in lines(from: stderrPipe) {
                AppLogger.backend.error("\(line, privacy: .public)")
            }
        }

        do {
            try proc.run()
        } catch {
            await setState(.crashed(reason: "spawn failed: \(error.localizedDescription)"))
            throw BackendProcessError.spawnFailed(error.localizedDescription)
        }

        self.process = proc

        let lockfile = try await waitForLockfile()
        let client = BackendClient(lockfile: lockfile)
        try await waitForHealth(client: client)

        restartAttempts = 0
        await setState(.ready(client))
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }

        guard let proc = process, proc.isRunning else {
            await setState(.stopped)
            return
        }

        let pid = proc.processIdentifier
        // SIGTERM grace before SIGKILL — keeps Python's atexit handlers running
        kill(pid, SIGTERM)

        let deadline = Date().addingTimeInterval(3)
        while proc.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if proc.isRunning {
            kill(pid, SIGKILL)
        }

        await setState(.stopped)
        process = nil
    }

    func states() -> AsyncStream<State> {
        AsyncStream { continuation in
            stateContinuations.append(continuation)
            continuation.yield(state)
        }
    }

    private func setState(_ newState: State) async {
        state = newState
        for continuation in stateContinuations {
            continuation.yield(newState)
        }
    }

    private func handleTermination() async {
        if isStopping {
            return
        }
        switch state {
        case .stopped, .crashed, .restarting:
            break
        case .starting, .ready:
            let exitCode = process?.terminationStatus ?? -1
            await scheduleRestart(reason: "process exited with code \(exitCode)")
        }
    }

    private func scheduleRestart(reason: String) async {
        let maxAttempts = 3
        guard restartAttempts < maxAttempts else {
            await setState(.crashed(reason: "\(reason); max restart attempts reached"))
            return
        }
        restartAttempts += 1
        let attempt = restartAttempts
        await setState(.restarting(attempt: attempt))
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard case .restarting = state else { return }
        AppLogger.backend.info("auto-restart attempt \(attempt)/\(maxAttempts)")
        try? await start(extraEnv: lastExtraEnv)
    }

    private func waitForLockfile() async throws -> Lockfile {
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < 5 {
            if let lockfile = try? readLockfile() {
                return lockfile
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if let proc = process {
            kill(proc.processIdentifier, SIGTERM)
        }
        await setState(.crashed(reason: "no lockfile after 5s"))
        throw BackendProcessError.noLockfile
    }

    private func waitForHealth(client: BackendClient) async throws {
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < 30 {
            if let status = try? await client.health(), status == .ready {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        if let proc = process {
            kill(proc.processIdentifier, SIGTERM)
        }
        await setState(.crashed(reason: "health timeout"))
        throw BackendProcessError.healthTimeout
    }
}

private func makeShortTimeoutSession(timeout: TimeInterval) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeout
    config.timeoutIntervalForResource = timeout
    return URLSession(configuration: config)
}

private func isPidAlive(_ pid: Int32) -> Bool {
    let result = kill(pid, 0)
    if result == 0 { return true }
    return errno == EPERM
}

private func lines(from pipe: Pipe) -> AsyncStream<String> {
    AsyncStream { continuation in
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                continuation.finish()
                return
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    continuation.yield(trimmed)
                }
            }
        }
    }
}
