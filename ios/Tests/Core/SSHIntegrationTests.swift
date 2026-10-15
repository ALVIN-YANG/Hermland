import CryptoKit
import Foundation
import NIOCore
import NIOSSH
import XCTest
@testable import HermlandCore

final class SSHIntegrationTests: XCTestCase {
    @MainActor
    func testRealUpstreamPagesAuthenticationAndReadOnlyRPC() async throws {
        guard ProcessInfo.processInfo.environment["HERMLAND_IOS_UPSTREAM_TEST"] == "isolated" else {
            throw XCTSkip("Requires disposable upstream image and pinned Hermes source checkout.")
        }
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let repo = tests.deletingLastPathComponent().deletingLastPathComponent()
        let docker = "/usr/local/bin/docker"
        let name = "hermland-ios-upstreams-" + UUID().uuidString.lowercased()
        try command(docker, ["run", "-d", "--name", name, "--label", "hermland.test=ios-upstreams",
                             "-p", "127.0.0.1::22", "-v", tests.appendingPathComponent("upstreams").path + ":/fixture:ro",
                             "-v", repo.appendingPathComponent(".build/upstreams/hermes-webui").path + ":/hermes:ro",
                             "hermland-ios-upstreams:local", "python3", "/fixture/start.py"])
        var completed = false
        defer {
            if !completed, var log = try? command(docker, ["logs", "--tail", "80", name], mergeError: true) {
                if let raw = try? command(docker, ["exec", name, "cat", "/tmp/hermland-upstreams/test-credentials.json"]),
                   let credentials = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: String] {
                    for secret in credentials.values { log = log.replacingOccurrences(of: secret, with: "[ephemeral-test-secret]") }
                }
                print(log)
            }
            _ = try? command(docker, ["rm", "-f", name])
        }
        var ready = false
        for _ in 0..<120 {
            if (try? command(docker, ["exec", name, "python3", "-c",
                                     "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/health',timeout=1); urllib.request.urlopen('http://127.0.0.1:18789/healthz',timeout=1)"])) != nil {
                ready = true; break
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        guard ready else { throw SSHConnectionError.process("Isolated real upstreams did not become healthy.") }
        let portText = try command(docker, ["port", name, "22/tcp"])
        let port = try XCTUnwrap(Int(portText.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").last!))
        let host = try command(docker, ["exec", name, "cat", "/tmp/hermland-test-host.pub"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = try DeviceIdentity(rawRepresentation: Curve25519.Signing.PrivateKey().rawRepresentation)
        let pub = "restrict,port-forwarding,command=\"/bin/false\",permitopen=\"127.0.0.1:9000\",permitopen=\"127.0.0.1:18789\" " + identity.publicKey
        try command(docker, ["exec", name, "python3", "-c",
                             "import pathlib,sys; pathlib.Path('/etc/hermland/ssh-devices/hl-upstream001.pub').write_text(sys.argv[1]+chr(10))", pub])
        let credentials = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(command(docker, ["exec", name, "cat", "/tmp/hermland-upstreams/test-credentials.json"]).utf8)) as? [String: String])
        var config = SSHConfiguration(host: "127.0.0.1", port: port, user: "hl-upstream001",
                                      remotePort: 9000, localPort: 39123, serverPublicKey: host)
        let hermes = SSHTransport()
        defer { hermes.close() }
        _ = try await hermes.start(configuration: config, identity: identity)
        try await BackendProbe.check(config)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let sessionsURL = URL(string: "http://127.0.0.1:39123/api/sessions")!
        let unauthorized = try await session.data(from: sessionsURL)
        XCTAssertEqual((unauthorized.1 as? HTTPURLResponse)?.statusCode, 401)
        var login = URLRequest(url: URL(string: "http://127.0.0.1:39123/api/auth/login")!)
        login.httpMethod = "POST"
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try JSONSerialization.data(withJSONObject: ["password": "wrong-test-password"])
        let wrongPasswordReply = try await session.data(for: login)
        XCTAssertEqual((wrongPasswordReply.1 as? HTTPURLResponse)?.statusCode, 401)
        login.httpBody = try JSONSerialization.data(withJSONObject: ["password": try XCTUnwrap(credentials["password"])])
        let loginReply = try await session.data(for: login)
        XCTAssertEqual((loginReply.1 as? HTTPURLResponse)?.statusCode, 200)
        let sessionsReply = try await session.data(from: sessionsURL)
        XCTAssertEqual((sessionsReply.1 as? HTTPURLResponse)?.statusCode, 200)
        let hermesPage = try await session.data(from: config.localURL).0
        XCTAssertTrue(String(decoding: hermesPage, as: UTF8.self).lowercased().contains("hermes"))
        hermes.close()

        config.backend = .openclaw
        config.remotePort = 18789
        config.localPort = 39124
        let claw = SSHTransport()
        defer { claw.close() }
        _ = try await claw.start(configuration: config, identity: identity)
        try await BackendProbe.check(config)
        let html = String(decoding: try await session.data(from: config.localURL).0, as: UTF8.self)
        let pattern = try NSRegularExpression(pattern: "src=\"([^\"]+\\.js)\"")
        let match = try XCTUnwrap(pattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: html))
        let asset = try XCTUnwrap(URL(string: String(html[range]), relativeTo: config.localURL)?.absoluteURL)
        let assetReply = try await session.data(from: asset)
        XCTAssertEqual((assetReply.1 as? HTTPURLResponse)?.statusCode, 200)
        let build = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(command(docker, ["exec", name, "cat", "/usr/local/lib/node_modules/openclaw/dist/build-info.json"]).utf8)) as? [String: Any])
        let noToken = try await gatewayHealth(session, build: build, token: nil, includeDevice: true)
        XCTAssertEqual(noToken["ok"] as? Bool, false)
        let wrongToken = try await gatewayHealth(session, build: build, token: "wrong-test-token", includeDevice: true)
        XCTAssertEqual(wrongToken["ok"] as? Bool, false)
        let noDevice = try await gatewayHealth(session, build: build, token: credentials["token"], includeDevice: false)
        XCTAssertEqual(noDevice["ok"] as? Bool, false)
        let health = try await gatewayHealth(session, build: build, token: credentials["token"], includeDevice: true)
        XCTAssertEqual(health["ok"] as? Bool, true)
        completed = true
        // No request in this test starts a model, sends chat, or modifies an existing Agent.
    }

    private func gatewayHealth(_ session: URLSession, build: [String: Any], token: String?, includeDevice: Bool) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "ws://127.0.0.1:39124")!)
        request.setValue("http://127.0.0.1:39124", forHTTPHeaderField: "Origin")
        let ws = session.webSocketTask(with: request)
        ws.resume()
        let watchdog = Task { try await Task.sleep(for: .seconds(10)); ws.cancel(with: .goingAway, reason: nil) }
        defer { watchdog.cancel(); ws.cancel(with: .normalClosure, reason: nil) }
        let key = Curve25519.Signing.PrivateKey()
        let bytes = key.publicKey.rawRepresentation
        let deviceID = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        func base64url(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        for _ in 0..<8 {
            let data: Data
            switch try await ws.receive() {
            case .data(let value): data = value
            case .string(let value): data = Data(value.utf8)
            @unknown default: throw SSHConnectionError.process("Unknown WebSocket frame.")
            }
            let message = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            if message["event"] as? String == "connect.challenge" {
                let challenge = try XCTUnwrap(message["payload"] as? [String: Any])
                let nonce = try XCTUnwrap(challenge["nonce"] as? String)
                let timestamp = try XCTUnwrap(challenge["ts"] as? NSNumber)
                let payload = ["v3", deviceID, "openclaw-control-ui", "webchat", "operator", "operator.read", timestamp.stringValue, token ?? "", nonce, "web", ""].joined(separator: "|")
                var params: [String: Any] = ["minProtocol": 4, "maxProtocol": 4,
                    "client": ["id": "openclaw-control-ui", "version": try XCTUnwrap(build["version"] as? String), "buildId": try XCTUnwrap(build["buildId"] as? String), "platform": "web", "mode": "webchat"],
                    "role": "operator", "scopes": ["operator.read"], "caps": [], "auth": token.map { ["token": $0] } ?? [:]]
                if includeDevice {
                    params["device"] = ["id": deviceID, "publicKey": base64url(bytes), "signature": base64url(try key.signature(for: Data(payload.utf8))), "signedAt": timestamp, "nonce": nonce]
                }
                try await ws.send(.data(JSONSerialization.data(withJSONObject: ["type": "req", "id": "connect", "method": "connect", "params": params])))
            } else if message["id"] as? String == "connect" {
                if message["ok"] as? Bool != true { return message }
                try await ws.send(.data(JSONSerialization.data(withJSONObject: ["type": "req", "id": "health", "method": "health", "params": [String: String]()])))
            } else if message["id"] as? String == "health" { return message }
        }
        throw SSHConnectionError.process("Expected Gateway health response was not received.")
    }

    @MainActor
    func testRealSSHForwardingIdentityRejectionAndRevocation() async throws {
        guard ProcessInfo.processInfo.environment["HERMLAND_IOS_SSH_TEST"] == "isolated" else {
            throw XCTSkip("Run with HERMLAND_IOS_SSH_TEST=isolated and Docker fixture.")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let name = "hermland-ios-ssh-" + UUID().uuidString.lowercased()
        let docker = "/usr/local/bin/docker"
        try command(docker, ["run", "-d", "--name", name, "--label", "hermland.test=ios",
                             "-p", "127.0.0.1::22", "-e", "HERMLAND_IOS_TEST=isolated",
                             "-v", root.appendingPathComponent("fixture").path + ":/fixture:ro",
                             "hermland-ssh-check:local", "bash", "/fixture/start.sh"])
        defer {
            if let log = try? command(docker, ["logs", name], mergeError: true) { print(log) }
            _ = try? command(docker, ["rm", "-f", name])
        }
        let portText = try command(docker, ["port", name, "22/tcp"])
        let port = try XCTUnwrap(Int(portText.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").last!))
        var host = ""
        for _ in 0..<30 {
            host = ((try? command(docker, ["exec", name, "cat", "/tmp/hermland-test-host.pub"])) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if host.hasPrefix("ssh-ed25519 ") { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let key = try DeviceIdentity(rawRepresentation: Curve25519.Signing.PrivateKey().rawRepresentation)
        let otherKey = try DeviceIdentity(rawRepresentation: Curve25519.Signing.PrivateKey().rawRepresentation)
        let pub = "restrict,port-forwarding,command=\"/bin/false\",permitopen=\"127.0.0.1:9000\" " + key.publicKey
        // Only a fresh, labelled test container receives this public key; never a user's VPS.
        try command(docker, ["exec", name, "python3", "-c",
                             "import pathlib,sys; pathlib.Path('/etc/hermland/ssh-devices/hl-iphone001.pub').write_text(sys.argv[1]+chr(10))", pub])
        var config = SSHConfiguration(host: "127.0.0.1", port: port, user: "hl-iphone001",
                                      remotePort: 9000, localPort: 39121, serverPublicKey: host)
        let tunnel = SSHTransport()
        defer { tunnel.close() }
        _ = try await tunnel.start(configuration: config, identity: key)
        try await BackendProbe.check(config)
        try command(docker, ["exec", name, "touch", "/tmp/hermland-fixture-outside"])
        do { try await BackendProbe.check(config); XCTFail("Cross-origin redirect accepted") } catch {}
        try command(docker, ["exec", name, "python3", "-c", "__import__('pathlib').Path('/tmp/hermland-fixture-outside').unlink()"])
        config.backend = .openclaw
        config.controlUIPath = "/openclaw/"
        try await BackendProbe.check(config)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let large = try await session.data(from: URL(string: "http://127.0.0.1:39121/large")!).0
        XCTAssertEqual(large, Data(repeating: 120, count: 262144))
        let sse = try await session.data(from: URL(string: "http://127.0.0.1:39121/sse")!).0
        XCTAssertTrue(String(decoding: sse, as: UTF8.self).contains("data: done"))
        for _ in 0..<10 {
            let short = try await session.data(from: URL(string: "http://127.0.0.1:39121/close")!).0
            XCTAssertEqual(String(decoding: short, as: UTF8.self), "short-connection-response")
        }
        let ws = session.webSocketTask(with: URL(string: "ws://127.0.0.1:39121/ws")!)
        ws.resume()
        try await ws.send(.string("hello"))
        let watchdog = Task {
            try await Task.sleep(for: .seconds(8))
            ws.cancel(with: .goingAway, reason: nil)
        }
        defer { watchdog.cancel() }
        if case .string(let message) = try await ws.receive() { XCTAssertEqual(message, "hello") }
        else { XCTFail("WebSocket returned wrong type") }
        ws.cancel(with: .normalClosure, reason: nil)

        var wrongHost = config
        wrongHost.localPort = 39122
        wrongHost.serverPublicKey = otherKey.publicKey
        await assertRejected(wrongHost, key)
        var unauthorized = config
        unauthorized.localPort = 39122
        await assertRejected(unauthorized, otherKey)
        var prohibited = config
        prohibited.localPort = 39122
        prohibited.remotePort = 9001
        let restricted = SSHTransport()
        _ = try await restricted.start(configuration: prohibited, identity: key)
        do { try await BackendProbe.check(prohibited); XCTFail("permitopen bypassed") } catch {}
        restricted.close()

        let disconnected = expectation(description: "revocation closes active SSH")
        tunnel.onDisconnect = { disconnected.fulfill() }
        try command(docker, ["exec", name, "python3", "-c",
                             "import os,pathlib,signal; pathlib.Path('/etc/hermland/ssh-devices/hl-iphone001.pub').rename('/etc/hermland/ssh-devices/hl-iphone001.revoked'); uid=__import__('pwd').getpwnam('hl-iphone001').pw_uid; [(os.kill(int(p.name),signal.SIGTERM)) for p in pathlib.Path('/proc').iterdir() if p.name.isdigit() and p.stat().st_uid==uid]"])
        await fulfillment(of: [disconnected], timeout: 5)
        await assertRejected(unauthorized, key)
    }

    @MainActor
    private func assertRejected(_ config: SSHConfiguration, _ key: DeviceIdentity) async {
        let transport = SSHTransport()
        defer { transport.close() }
        do { _ = try await transport.start(configuration: config, identity: key); XCTFail("Unexpected authentication success") }
        catch {}
    }

    @discardableResult
    private func command(_ executable: String, _ arguments: [String], mergeError: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = mergeError ? output : error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SSHConnectionError.process("Isolated fixture command failed: " + String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
