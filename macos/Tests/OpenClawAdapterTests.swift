import XCTest
@testable import Hermland

final class OpenClawAdapterTests: XCTestCase {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnAc33IigsphK1ZXasje0U/gOKbBuiSO75mI0xGkVlZ"

    func testOldJSONDefaultsToHermesAndUnknownBackendFails() throws {
        let old = #"{"host":"relay.example.com","port":22,"user":"hl-device0001","remotePort":19119,"localPort":19121,"serverPublicKey":"KEY"}"#
            .replacingOccurrences(of: "KEY", with: key)
        let value = try JSONDecoder().decode(SSHConfiguration.self, from: Data(old.utf8)).validated()
        XCTAssertEqual(value.backend, .hermes)
        XCTAssertEqual(value.controlUIPath, "/")
        let unknown = old.dropLast() + #", "backend":"other"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(SSHConfiguration.self, from: Data(unknown.utf8)))
        var openclaw = value
        openclaw.backend = .openclaw
        openclaw.controlUIPath = "/openclaw"
        let encoded = try JSONEncoder().encode(openclaw)
        XCTAssertEqual(try JSONDecoder().decode(SSHConfiguration.self, from: encoded).validated().controlUIPath, "/openclaw/")
    }

    func testUIPathCannotReplaceLoopbackOriginOrCarryCredentials() throws {
        var config = SSHConfiguration(host: "relay.example.com", user: "hl-device0001", serverPublicKey: key, backend: .openclaw)
        config.controlUIPath = "/openclaw"
        let valid = try config.validated()
        XCTAssertEqual(valid.localURL.absoluteString, "http://127.0.0.1:19121/openclaw/")
        for path in ["//evil.example", "https://evil.example", "/?token=secret", "/#token=secret", "/../", "/%2e%2e/", "/a//b"] {
            config.controlUIPath = path
            XCTAssertThrowsError(try config.validated(), path)
        }
    }

    func testBrowserCredentialsAreScopedToTrustedSSHRoute() {
        let config = SSHConfiguration(host: "relay.example.com", user: "hl-device0001", serverPublicKey: key, backend: .openclaw)
        XCTAssertEqual(config.websiteDataStoreID, config.websiteDataStoreID)
        for change in [
            { (c: inout SSHConfiguration) in c.host = "other.example.com" },
            { c in c.user = "hl-other0001" },
            { c in c.remotePort = 19219 },
            { c in c.serverPublicKey += "changed" },
            { c in c.backend = .hermes },
            { c in c.controlUIPath = "/other/" },
        ] {
            var other = config
            change(&other)
            XCTAssertNotEqual(config.websiteDataStoreID, other.websiteDataStoreID)
        }
    }

    func testProbeUsesOpenClawHealthAndCustomUIPathWithoutHermesRPC() async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [OpenClawResponseProtocol.self]
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel() }
        var requestedPaths: [String] = []
        OpenClawResponseProtocol.respond = { request in
            requestedPaths.append(request.url!.path)
            if request.url!.path == "/healthz" {
                return (200, #"{"ok":true,"status":"live","version":"2026.9.9"}"#)
            }
            return (200, "<html><openclaw-app></openclaw-app></html>")
        }
        let config = SSHConfiguration(backend: .openclaw, controlUIPath: "/openclaw/")
        let status = try await OpenClawProbe.probe(config, session: session)
        XCTAssertEqual(requestedPaths, ["/healthz", "/openclaw"])
        XCTAssertEqual(status.version, "2026.9.9")
        XCTAssertTrue(status.authRequired) // HTTP reachability never claims an authenticated Gateway session.
    }

    func testProbeRejectsWrongBackendAndMissingControlUI() async throws {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [OpenClawResponseProtocol.self]
        let session = URLSession(configuration: settings)
        defer { session.invalidateAndCancel() }
        for payload in [#"{"status":"ok"}"#, #"{"ok":false,"status":"live"}"#, #"{"ok":true,"status":"starting"}"#] {
            OpenClawResponseProtocol.respond = { _ in (200, payload) }
            do {
                _ = try await OpenClawProbe.probe(SSHConfiguration(backend: .openclaw), session: session)
                XCTFail("Wrong health contract accepted")
            } catch { }
        }
        OpenClawResponseProtocol.respond = { request in
            request.url!.path == "/healthz" ? (200, #"{"ok":true,"status":"live"}"#) : (200, "<html>Another app</html>")
        }
        do {
            _ = try await OpenClawProbe.probe(SSHConfiguration(backend: .openclaw), session: session)
            XCTFail("Missing Control UI accepted")
        } catch { }
    }
}

private final class OpenClawResponseProtocol: URLProtocol {
    static var respond: ((URLRequest) -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                            httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
