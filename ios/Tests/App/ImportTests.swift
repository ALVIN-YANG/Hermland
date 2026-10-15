import XCTest
import HermlandCore
import Security
@testable import Hermland

final class ImportTests: XCTestCase {
    func testDoesNotAcceptOversizedConfiguration() {
        XCTAssertThrowsError(try ConnectionImport.decode(Data(repeating: 32, count: 65_537)))
    }
    func testDeviceIdentitySurvivesReloadWithoutChangingPublicKey() throws {
        let service = "land.hermland.test." + UUID().uuidString
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: service] as CFDictionary)
        }
        let original = try DeviceIdentity.loadOrCreate(service: service)
        let reloaded = try DeviceIdentity.loadOrCreate(service: service)
        XCTAssertEqual(original.publicKey, reloaded.publicKey)
        XCTAssertEqual(original.fingerprint, reloaded.fingerprint)
        XCTAssertNoThrow(try SSHConfiguration.normalizedPublicKey(original.publicKey))
    }
}
