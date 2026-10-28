import Foundation
import Network

/// Compile-time privacy switches for this fork. Set them in SWIFT_ACTIVE_COMPILATION_CONDITIONS;
/// see PRIVACY.md for what each one removes.
nonisolated enum ForkBuildPolicy {
    /// `FLUID_NO_ANALYTICS`: no analytics events are recorded locally or uploaded.
    static let analyticsCompiledOut: Bool = {
        #if FLUID_NO_ANALYTICS
        true
        #else
        false
        #endif
    }()

    /// `FLUID_NO_UPDATER`: no release checks, downloads or self-replacement from GitHub.
    static let updaterCompiledOut: Bool = {
        #if FLUID_NO_UPDATER
        true
        #else
        false
        #endif
    }()

    /// `FLUID_LOCAL_ONLY`: text (prompts, transcripts, feedback) may only go to loopback,
    /// or to hosts baked into Info.plist under `FluidEgressAllowlist` at build time.
    static let localOnlyEgress: Bool = {
        #if FLUID_LOCAL_ONLY
        true
        #else
        false
        #endif
    }()

    static let localOnlyRejectionMessage =
        "This build only sends text to loopback endpoints (localhost, 127.0.0.0/8, ::1). See PRIVACY.md."

    /// Whether text may be sent to `url` under the current build policy.
    static func allowsTextEgress(to url: URL?) -> Bool {
        guard self.localOnlyEgress else { return true }
        guard let url, let host = url.host?.lowercased(), !host.isEmpty else { return false }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return self.isLoopback(host: host) || self.bakedAllowlist.contains(host)
    }

    static func allowsTextEgress(to urlString: String) -> Bool {
        self.allowsTextEgress(to: URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    static func isLoopback(host rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if host == "localhost" { return true }
        if let address = IPv4Address(host) { return address.rawValue.first == 127 }
        if let address = IPv6Address(host) { return address == IPv6Address.loopback }
        return false
    }

    /// Exact host names, read from the signed bundle so it cannot be changed at runtime.
    private static let bakedAllowlist: Set<String> = {
        let entries = Bundle.main.object(forInfoDictionaryKey: "FluidEgressAllowlist") as? [String] ?? []
        return Set(entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }()
}

/// Refuses HTTP redirects that would leave the egress policy, so an allowed loopback endpoint cannot
/// forward a request elsewhere. Pass as the task delegate of every text-carrying request.
final nonisolated class EgressRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = EgressRedirectGuard()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(ForkBuildPolicy.allowsTextEgress(to: request.url) ? request : nil)
    }
}
