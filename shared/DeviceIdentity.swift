import CryptoKit
import Foundation
import Security
import NIOSSH

/// Private material never leaves Keychain or process memory on iOS.
public struct DeviceIdentity: Sendable {
    let key: Curve25519.Signing.PrivateKey // gitleaks:allow -- CryptoKit type name, not a secret literal.
    public var publicKey: String { String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: key).publicKey) }
    public var fingerprint: String { SSHConfiguration.fingerprint(publicKey)! }

    public init(rawRepresentation: Data) throws {
        key = try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }

    public static func loadOrCreate(service: String = "land.hermland.ios") throws -> DeviceIdentity {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: "ssh.device.ed25519.v1"]
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return try DeviceIdentity(rawRepresentation: data) }
        guard status == errSecItemNotFound else { throw SSHConnectionError.keychain(status) }
        let key = Curve25519.Signing.PrivateKey()
        var insert = query
        insert[kSecValueData as String] = key.rawRepresentation
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        insert[kSecAttrSynchronizable as String] = false
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw SSHConnectionError.keychain(added) }
        return try DeviceIdentity(rawRepresentation: key.rawRepresentation)
    }
}
