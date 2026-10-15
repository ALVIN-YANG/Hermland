import XCTest
@testable import HermlandCore

final class ConfigurationTests: XCTestCase {
    func testRejectsUntrustedHostKeyAndRoot() throws {
        XCTAssertThrowsError(try SSHConfiguration(host: "relay.example.com", user: "root").validated())
        XCTAssertThrowsError(try SSHConfiguration(host: "relay.example.com", user: "hl-phone001",
                                                 serverPublicKey: "SHA256:not-a-public-key").validated())
    }
    func testPathsCannotCarryCredentialsOrEscapeOrigin() throws {
        for path in ["//attacker.example", "/../private", "/ui?token=secret", "/ui#token", "https://example.com"] {
            XCTAssertThrowsError(try AgentBackend.normalizedUIPath(path))
        }
        XCTAssertEqual(try AgentBackend.normalizedUIPath("/openclaw"), "/openclaw/")
    }
}
