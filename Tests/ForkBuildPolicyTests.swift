import Foundation

@main
struct ForkBuildPolicyTests {
    static func main() {
        // Compiled with -D FLUID_LOCAL_ONLY by Tests/run_fork_build_policy_tests.sh.
        precondition(ForkBuildPolicy.localOnlyEgress)
        for allowed in [
            "http://localhost:1234/v1", "http://127.0.0.1:11434/v1", "https://127.0.0.1:8080/v1",
            "http://127.1.2.3/v1", "http://[::1]:8080/v1", "http://LOCALHOST/v1",
        ] {
            precondition(ForkBuildPolicy.allowsTextEgress(to: allowed), allowed)
        }
        for blocked in [
            "https://api.openai.com/v1", "http://127.0.0.1.nip.io/v1", "http://localhost.example.com/v1",
            "http://192.168.1.10:1234/v1", "http://10.0.0.1/v1", "http://[::2]/v1", "file:///etc/passwd",
            "ftp://127.0.0.1/", "", "not a url", "http://0.0.0.0:1234/v1",
        ] {
            precondition(!ForkBuildPolicy.allowsTextEgress(to: blocked), blocked)
        }

        let token = String(repeating: "a", count: 64)
        func request(_ headers: [String: String]) -> LocalAPI.Request {
            LocalAPI.Request(method: "GET", path: "/v1/history", query: [:], headers: headers, body: Data())
        }
        let auth = "Bearer \(token)"
        precondition(LocalAPIAccessPolicy.rejection(for: request(["host": "127.0.0.1:47733", "authorization": auth]), port: 47_733, token: token) == nil)
        precondition(LocalAPIAccessPolicy.rejection(for: request(["host": "localhost:47733", "authorization": auth]), port: 47_733, token: token) == nil)
        precondition(LocalAPIAccessPolicy.rejection(for: request(["host": "[::1]:47733", "authorization": auth]), port: 47_733, token: token) == nil)
        precondition(LocalAPIAccessPolicy.rejection(for: request(["host": "evil.example:47733", "authorization": auth]), port: 47_733, token: token)?.status == 403, "DNS rebinding")
        precondition(LocalAPIAccessPolicy.rejection(for: request(["host": "127.0.0.1:1", "authorization": auth]), port: 47_733, token: token)?.status == 403)
        precondition(LocalAPIAccessPolicy.rejection(for: request(["authorization": auth]), port: 47_733, token: token)?.status == 403, "Host is required")
        let browserRequest = request(["host": "127.0.0.1:47733", "authorization": auth, "origin": "https://evil.example"])
        precondition(LocalAPIAccessPolicy.rejection(for: browserRequest, port: 47_733, token: token)?.status == 403, "Browser origin")
        precondition(LocalAPIAccessPolicy.rejection(for: request(["host": "127.0.0.1:47733"]), port: 47_733, token: token)?.status == 401)
        let wrongToken = request(["host": "127.0.0.1:47733", "authorization": "Bearer " + String(repeating: "b", count: 64)])
        precondition(LocalAPIAccessPolicy.rejection(for: wrongToken, port: 47_733, token: token)?.status == 401)
        precondition(!LocalAPIAccessPolicy.constantTimeEquals("", ""), "Empty token never matches")
        print("ForkBuildPolicyTests passed")
    }
}
