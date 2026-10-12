import XCTest
@testable import Hermland

final class OnboardingTests: XCTestCase {
    func testHermesHTTPTransportDoesNotReuseGlobalCookiesOrProxy() {
        let profile = HermesClient.sessionConfiguration()
        XCTAssertFalse(profile.httpCookieStorage === HTTPCookieStorage.shared)
        XCTAssertEqual(profile.connectionProxyDictionary?.count, 0)
        XCTAssertEqual(profile.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertTrue(profile.httpShouldSetCookies) // Legacy login still works within this client instance.
    }
    func testFingerprintMatchesOpenSSHAndRejectsInvalidKey() {
        let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnAc33IigsphK1ZXasje0U/gOKbBuiSO75mI0xGkVlZ"
        XCTAssertEqual(SSHConfiguration.fingerprint(key), "SHA256:j17NwLkJjVp/8M251+iXDdkExN9Rg4KaWZK93Rl7lQk")
        XCTAssertNil(SSHConfiguration.fingerprint("not-a-key"))
    }
    func testPromptKeepsManualApprovalAndExistingBackend() {
        for backend in AgentBackend.allCases {
            let prompt = OnboardingInstructions.prompt(for: backend)
            XCTAssertTrue(prompt.contains("每次授权前必须获得我"))
            XCTAssertTrue(prompt.contains("不能主动申请或自动审批"))
            XCTAssertTrue(prompt.contains("不重装、不升级、不迁移"))
            XCTAssertTrue(prompt.contains("模型测试由我本人发送"))
        }
        XCTAssertTrue(OnboardingInstructions.prompt(for: .openclaw).contains("--backend openclaw"))
        XCTAssertTrue(OnboardingInstructions.prompt(for: .openclaw).contains("不安装 Hermes"))
        XCTAssertFalse(OnboardingInstructions.prompt(for: .hermes).contains("--backend openclaw"))
    }

    func testCompleteRequestContainsPublicKeyAndNeedsSeparateApproval() throws {
        let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnAc33IigsphK1ZXasje0U/gOKbBuiSO75mI0xGkVlZ"
        for backend in AgentBackend.allCases {
            let request = try OnboardingInstructions.request(for: backend, purpose: .firstSetup, publicKey: key)
            XCTAssertTrue(request.contains(key))
            XCTAssertTrue(request.contains(SSHConfiguration.fingerprint(key)!))
            XCTAssertTrue(request.contains("这份材料不是授权"))
            XCTAssertTrue(request.contains("另行明确确认"))
            XCTAssertFalse(request.contains("PRIVATE KEY"))
        }
        let additional = try OnboardingInstructions.request(for: .openclaw, purpose: .additionalDevice, publicKey: key)
        XCTAssertTrue(additional.contains("不要安装、升级或重建"))
        XCTAssertTrue(additional.contains("已有中转不通时停下报告"))
        XCTAssertThrowsError(try OnboardingInstructions.request(for: .hermes, purpose: .firstSetup, publicKey: ""))
        XCTAssertThrowsError(try OnboardingInstructions.request(for: .hermes, purpose: .firstSetup, publicKey: key + "\nextra"))
    }

    @MainActor
    func testReadingConfigurationDoesNotReplaceSavedRouteOrConnect() throws {
        let store = AppState()
        let original = store.sshConfiguration
        let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnAc33IigsphK1ZXasje0U/gOKbBuiSO75mI0xGkVlZ"
        let candidate = SSHConfiguration(host: "example.invalid", user: "hl-test", serverPublicKey: key)
        let folder = try SSHIdentity.privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("connection.json")
        try JSONEncoder().encode(candidate).write(to: file)
        XCTAssertEqual(try store.readSSHConfiguration(from: file), candidate)
        XCTAssertEqual(store.sshConfiguration, original)
        XCTAssertFalse(store.isConnecting)
        XCTAssertFalse(store.isConnected)
        try Data("{}".utf8).write(to: file)
        XCTAssertThrowsError(try store.readSSHConfiguration(from: file))
        XCTAssertEqual(store.sshConfiguration, original)
    }

    func testFailureDoesNotMarkLaterChecksPassedOrLeakHTTPBody() {
        var checks = ConnectionDiagnostics()
        checks.update(.configuration, .passed)
        checks.update(.deviceKey, .passed)
        checks.update(.ssh, .passed)
        checks.update(.agent, .running)
        let message = checks.fail(HermlandError.http(401, "secret-api-key private-message"))
        XCTAssertTrue(message.contains("401"))
        let report = checks.report(backend: .hermes, version: "test")
        XCTAssertFalse(report.contains("secret-api-key"))
        XCTAssertFalse(report.contains("private-message"))
        XCTAssertEqual(checks.checks.last?.result, .failed)
        XCTAssertTrue(report.contains("未由本检查验证"))
        var fresh = ConnectionDiagnostics()
        fresh.update(.ssh, .running)
        _ = fresh.fail(SSHConnectionError.process("设备尚未授权。"))
        XCTAssertEqual(fresh.checks.last?.result, .waiting)
    }

    func testBundledGuideAndSetupArchiveContainNoUserKeys() async throws {
        XCTAssertTrue(try SetupResources.guide().contains("快速开始"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("setup.zip")
        try await Task.detached { try SetupResources.export(to: archive) }.value
        XCTAssertThrowsError(try SetupResources.export(to: archive))
        let process = Process()
        let extracted = folder.appendingPathComponent("extracted")
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, extracted.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let root = extracted.appendingPathComponent("HermlandSetup")
        for name in ["deploy/ssh_policy.py", "docs/快速开始.md", "README.en.md", "LICENSE", "assets/readme/panorama.png",
                     "assets/readme/how-it-works.svg", "assets/readme/how-it-works.en.svg", "SECURITY.md",
                     "docs/发布与验收.md", "CONTRIBUTING.md"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), name)
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("deploy").path)
        XCTAssertEqual(entries.count, 7)
        XCTAssertFalse(entries.contains("identity"))
        XCTAssertFalse(entries.contains(".env"))
        XCTAssertFalse(entries.contains("__pycache__"))
    }
}
