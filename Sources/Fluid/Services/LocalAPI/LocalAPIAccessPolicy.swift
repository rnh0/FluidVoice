import Foundation
import Security

/// Checks applied to every Local API request before routing.
///
/// The API exposes history, meeting transcripts and the boosting dictionary, so loopback alone is
/// not enough: browsers can reach 127.0.0.1 through DNS rebinding or cross-site form posts.
/// Requests must carry a loopback Host, no Origin, and `Authorization: Bearer <token>`, where the
/// token is read from `LocalAPIAccessPolicy.tokenFileURL` (created on first start, mode 0600).
enum LocalAPIAccessPolicy {
    static func rejection(for request: LocalAPI.Request, port: UInt16, token: String) -> LocalAPI.Response? {
        guard self.isLoopbackHost(request.headers["host"], port: port) else {
            return LocalAPI.error("Host not allowed.", status: 403)
        }
        guard request.headers["origin"] == nil else {
            return LocalAPI.error("Browser requests are not allowed.", status: 403)
        }
        guard let authorization = request.headers["authorization"],
              authorization.hasPrefix("Bearer "),
              self.constantTimeEquals(String(authorization.dropFirst("Bearer ".count)), token)
        else {
            return LocalAPI.error("Missing or invalid bearer token.", status: 401)
        }
        return nil
    }

    static func isLoopbackHost(_ header: String?, port: UInt16) -> Bool {
        guard let header = header?.lowercased(), !header.isEmpty else { return false }
        let allowedHosts = ["127.0.0.1", "localhost", "[::1]"]
        return allowedHosts.contains(header) || allowedHosts.contains { header == "\($0):\(port)" }
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count, !right.isEmpty else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    static var tokenFileURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return applicationSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "FluidVoice", isDirectory: true)
            .appendingPathComponent("local-api-token", isDirectory: false)
    }

    /// Returns the existing token, or creates one. Returns nil if no token can be stored,
    /// in which case the server must not start.
    static func loadOrCreateToken() -> String? {
        let url = self.tokenFileURL
        if let existing = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32
        {
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let token = bytes.map { String(format: "%02x", $0) }.joined()

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fileManager.createFile(
                atPath: url.path,
                contents: Data((token + "\n").utf8),
                attributes: [.posixPermissions: 0o600]
            ) else { return nil }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        return token
    }
}
