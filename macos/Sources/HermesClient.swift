import Foundation

actor HermesClient {
    private let session: URLSession
    private var settings: ConnectionSettings
    private var webSocket: URLSessionWebSocketTask?
    private var rpcID = 0
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var receiveTask: Task<Void, Never>?
    private var onEvent: (@Sendable (String, String, JSONValue) -> Void)?

    init(settings: ConnectionSettings) {
        self.settings = settings
        self.session = URLSession(configuration: Self.sessionConfiguration())
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        // A reused loopback address must not reuse another client's cookies or proxy route.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 30
        return configuration
    }

    func updateSettings(_ settings: ConnectionSettings) {
        self.settings = settings
    }

    func setEventHandler(_ handler: (@Sendable (String, String, JSONValue) -> Void)?) {
        onEvent = handler
    }

    func probe() async throws -> GatewayStatus {
        if let healthData = try? await get(path: "/health") {
            let health = try json(healthData)
            if health["status"]?.string == "ok" {
                let settingsValue: JSONValue
                if let settingsData = try? await get(path: "/api/settings") {
                    settingsValue = try json(settingsData)
                } else {
                    settingsValue = .object([:])
                }
                return SessionParser.statusFromWebUI(health: health, settings: settingsValue)
            }
        }
        let data = try await get(path: "/api/status")
        return SessionParser.status(from: try json(data))
    }

    func login() async throws {
        let body: [String: String] = [
            "provider": "basic",
            "username": settings.username,
            "password": settings.password,
        ]
        let data = try await post(path: "/auth/password-login", json: body)
        let value = try json(data)
        if value["ok"]?.bool == false {
            throw HermlandError.unauthorized
        }
    }

    func me() async throws -> String {
        let data = try await get(path: "/api/auth/me")
        let value = try json(data)
        return value["display_name"]?.string
            ?? value["username"]?.string
            ?? value["user_id"]?.string
            ?? settings.username
    }

    func listSessions() async throws -> [ChatSession] {
        let data = try await get(path: "/api/sessions?order=recent&limit=40&exclude_sources=cron")
        return SessionParser.sessions(from: try json(data))
    }

    func messages(sessionID: String) async throws -> [ChatMessage] {
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionID
        let data = try await get(path: "/api/sessions/\(encoded)/messages?order=oldest&limit=200")
        return SessionParser.messages(from: try json(data))
            .filter { !$0.text.isEmpty && $0.role != .system }
    }

    func connectSocket() async throws {
        disconnectSocket()
        let ticket = try await mintTicket()
        guard let base = settings.baseURL else { throw HermlandError.invalidURL }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.scheme = "ws"
        components?.path = "/api/ws"
        components?.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        guard let url = components?.url else { throw HermlandError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(base.host.map { "\($0):\(settings.port)" }, forHTTPHeaderField: "Host")
        let task = session.webSocketTask(with: request)
        webSocket = task
        task.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    struct BoundSession: Equatable {
        var liveID: String
        var storedID: String
    }

    func createSession() async throws -> BoundSession {
        let result = try await rpc("session.create", params: [
            "source": "desktop",
            "cols": 96,
        ])
        return try boundSession(from: result)
    }

    func resumeSession(_ id: String) async throws -> BoundSession {
        let result = try await rpc("session.resume", params: [
            "session_id": id,
            "omit_messages": true,
        ])
        return try boundSession(from: result)
    }

    private func boundSession(from result: JSONValue) throws -> BoundSession {
        guard let liveID = result["session_id"]?.string, !liveID.isEmpty else {
            throw HermlandError.rpc("网关没有返回可用的 session_id")
        }
        return BoundSession(
            liveID: liveID,
            storedID: result["stored_session_id"]?.string ?? liveID
        )
    }

    func submit(sessionID: String, text: String) async throws {
        _ = try await rpc("prompt.submit", params: [
            "session_id": sessionID,
            "text": text,
        ])
    }

    func disconnect() {
        disconnectSocket()
        pending.values.forEach { $0.resume(throwing: HermlandError.disconnected) }
        pending.removeAll()
    }

    private func mintTicket() async throws -> String {
        let data = try await post(path: "/api/auth/ws-ticket", json: [String: String]())
        guard let ticket = try json(data)["ticket"]?.string, !ticket.isEmpty else {
            throw HermlandError.rpc("没有拿到 WebSocket ticket")
        }
        return ticket
    }

    private func rpc(_ method: String, params: [String: Any]) async throws -> JSONValue {
        rpcID += 1
        let id = rpcID
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw HermlandError.decode
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            webSocket?.send(.string(text)) { [weak self] error in
                if let error {
                    Task { await self?.fail(id: id, error: error) }
                }
            }
        }
    }

    private func fail(id: Int, error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func receiveLoop() async {
        while let webSocket, !Task.isCancelled {
            do {
                let message = try await webSocket.receive()
                let text: String
                switch message {
                case .string(let value):
                    text = value
                case .data(let data):
                    text = String(data: data, encoding: .utf8) ?? ""
                @unknown default:
                    continue
                }
                handleIncoming(text)
            } catch {
                pending.values.forEach { $0.resume(throwing: HermlandError.disconnected) }
                pending.removeAll()
                break
            }
        }
    }

    private func handleIncoming(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        let value = JSONValue(object)
        if let id = value["id"]?.int {
            if let error = value["error"] {
                let message = error["message"]?.string ?? "RPC 失败"
                pending.removeValue(forKey: id)?.resume(throwing: HermlandError.rpc(message))
            } else {
                pending.removeValue(forKey: id)?.resume(returning: value["result"] ?? .null)
            }
            return
        }
        if value["method"]?.string == "event" {
            let params = value["params"]
            let type = params?["type"]?.string ?? ""
            let sessionID = params?["session_id"]?.string ?? ""
            onEvent?(type, sessionID, params?["payload"] ?? .null)
        }
    }

    private func disconnectSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    private func get(path: String) async throws -> Data {
        try await send(path: path, method: "GET", body: nil)
    }

    private func post(path: String, json: [String: Any]) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: json)
        return try await send(path: path, method: "POST", body: body)
    }

    private func send(path: String, method: String, body: Data?) async throws -> Data {
        guard let base = settings.baseURL, let url = URL(string: path, relativeTo: base) else {
            throw HermlandError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HermlandError.decode }
        if http.statusCode == 401 { throw HermlandError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw HermlandError.http(http.statusCode, String(snippet.prefix(200)))
        }
        return data
    }

    private func json(_ data: Data) throws -> JSONValue {
        let object = try JSONSerialization.jsonObject(with: data)
        return JSONValue(object)
    }
}
