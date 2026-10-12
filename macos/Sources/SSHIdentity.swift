import Foundation
import Security

struct SSHIdentity: Codable {
    let privateKey: Data
    let publicKey: String
    private static let account = "hermland.ssh.device.v1"
    private static let service = "land.hermland.client"

    static func loadOrCreate() throws -> SSHIdentity {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return try JSONDecoder().decode(SSHIdentity.self, from: data)
        }
        guard status == errSecItemNotFound else { throw SSHConnectionError.keychain(status) }

        let folder = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = folder.appendingPathComponent("identity")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-q", "-t", "ed25519", "-N", "", "-C", "Hermland-device", "-f", key.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SSHConnectionError.process("生成设备密钥失败") }
        let identity = SSHIdentity(
            privateKey: try Data(contentsOf: key),
            publicKey: try SSHConfiguration.normalizedPublicKey(String(contentsOf: URL(fileURLWithPath: key.path + ".pub")).trimmingCharacters(in: .whitespacesAndNewlines))
        )
        var item = query
        item.removeValue(forKey: kSecReturnData as String)
        item.removeValue(forKey: kSecMatchLimit as String)
        item[kSecValueData as String] = try JSONEncoder().encode(identity)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw SSHConnectionError.keychain(added) }
        return identity
    }

    static func privateTemporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hermland-ssh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return folder
    }

    func publishPublicKey() throws {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Hermland")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try (publicKey + "\n").write(to: folder.appendingPathComponent("ssh-device.pub"), atomically: true, encoding: .utf8)
    }
}
