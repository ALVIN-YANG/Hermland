import Foundation

/// Reachability only. Control UI owns Gateway login, pairing, sessions and chat RPCs.
enum OpenClawProbe {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func probe(_ configuration: SSHConfiguration, session suppliedSession: URLSession? = nil) async throws -> GatewayStatus {
        let session: URLSession
        if let suppliedSession {
            session = suppliedSession
        } else {
            let settings = URLSessionConfiguration.ephemeral
            settings.connectionProxyDictionary = [:]
            settings.httpShouldSetCookies = false
            settings.timeoutIntervalForRequest = 8
            settings.requestCachePolicy = .reloadIgnoringLocalCacheData
            session = URLSession(configuration: settings, delegate: NoRedirect(), delegateQueue: nil)
        }
        defer { if suppliedSession == nil { session.invalidateAndCancel() } }
        var components = URLComponents(url: configuration.localURL, resolvingAgainstBaseURL: false)!
        components.path = AgentBackend.openclaw.healthPath
        var healthRequest = URLRequest(url: components.url!)
        healthRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: healthRequest)
        let health = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              health?["status"] as? String == "live", health?["ok"] as? Bool == true else {
            throw SSHConnectionError.process("SSH 已连接，但 OpenClaw /healthz 未通过。请核对后端类型、端口与 Gateway 状态")
        }
        var uiRequest = URLRequest(url: configuration.localURL)
        uiRequest.setValue("text/html", forHTTPHeaderField: "Accept")
        let (html, uiResponse) = try await session.data(for: uiRequest)
        guard (uiResponse as? HTTPURLResponse)?.statusCode == 200,
              String(data: html, encoding: .utf8)?.contains("<openclaw-app") == true else {
            throw SSHConnectionError.process("OpenClaw Gateway 可达，但 Control UI 未启用或路径不对。请检查 gateway.controlUi")
        }
        return GatewayStatus(version: health?["version"] as? String ?? "—", model: "—", provider: "—",
                             gatewayRunning: true, activeSessions: 0, authRequired: true, authProviders: [])
    }
}
