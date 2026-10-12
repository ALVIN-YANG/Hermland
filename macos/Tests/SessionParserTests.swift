import XCTest
@testable import Hermland

final class SessionParserTests: XCTestCase {
    func testParsesSessionsAndMessages() throws {
        let payload: [String: Any] = [
            "sessions": [
                [
                    "id": "abc",
                    "title": "周末安排",
                    "preview": "帮我列一下",
                    "model": "deepseek-v4-flash",
                    "is_active": true,
                ],
            ],
        ]
        let sessions = SessionParser.sessions(from: JSONValue(payload))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, "abc")
        XCTAssertEqual(sessions[0].title, "周末安排")

        let messagesPayload: [String: Any] = [
            "messages": [
                ["role": "user", "content": "你好"],
                ["role": "assistant", "content": [["type": "text", "text": "在的"]]],
            ],
        ]
        let messages = SessionParser.messages(from: JSONValue(messagesPayload))
        XCTAssertEqual(messages.map(\.text), ["你好", "在的"])
    }

    func testSSHLoopbackBaseURL() {
        let settings = ConnectionSettings.default
        XCTAssertEqual(settings.baseURL?.scheme, "http")
        XCTAssertEqual(settings.baseURL?.host, "127.0.0.1")
        XCTAssertEqual(settings.baseURL?.port, 19121)
        XCTAssertEqual(settings.displayURL, "http://127.0.0.1:19121")
    }

    func testStatusDefaults() {
        let status = SessionParser.status(from: JSONValue([
            "version": "0.20.1",
            "gateway_running": false,
            "auth_required": true,
        ] as [String: Any]))
        XCTAssertEqual(status.version, "0.20.1")
        XCTAssertFalse(status.gatewayRunning)
        XCTAssertTrue(status.authRequired)
    }

    func testWebUIHealthStatus() {
        let status = SessionParser.statusFromWebUI(
            health: JSONValue([
                "status": "ok",
                "sessions": 2,
            ] as [String: Any]),
            settings: JSONValue([
                "webui_version": "exp-v0.52.232",
                "default_model": "deepseek-v4-flash",
                "default_model_provider": "deepseek",
                "auth_enabled": false,
            ] as [String: Any])
        )
        XCTAssertEqual(status.model, "deepseek-v4-flash")
        XCTAssertEqual(status.provider, "deepseek")
        XCTAssertTrue(status.gatewayRunning)
        XCTAssertFalse(status.authRequired)
        XCTAssertEqual(status.activeSessions, 2)
    }

    func testUnauthorizedCopy() {
        XCTAssertEqual(
            HermlandError.unauthorized.errorDescription,
            "Hermes 后端要求登录，请检查后端认证配置"
        )
    }
}
