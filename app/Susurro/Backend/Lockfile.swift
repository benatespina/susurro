import Foundation

struct Lockfile: Codable, Sendable {
    let port: Int
    let pid: Int32
    let token: String
    let startedAt: String

    enum CodingKeys: String, CodingKey {
        case port, pid, token
        case startedAt = "started_at"
    }
}

enum LockfileError: Error, Equatable {
    case missing
    case malformed(String)
}

enum LockfileLocator {
    static var path: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Application Support/Susurro/backend.lock")
    }
}

func readLockfile() throws -> Lockfile {
    let url = LockfileLocator.path
    guard let data = try? Data(contentsOf: url) else {
        throw LockfileError.missing
    }
    do {
        return try JSONDecoder().decode(Lockfile.self, from: data)
    } catch {
        throw LockfileError.malformed(error.localizedDescription)
    }
}
