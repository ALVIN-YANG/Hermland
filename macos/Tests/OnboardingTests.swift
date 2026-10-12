import XCTest
@testable import Hermland

final class OnboardingTests: XCTestCase {
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
        for name in ["deploy/ssh_policy.py", "docs/快速开始.md", "LICENSE"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path), name)
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("deploy").path)
        XCTAssertEqual(entries.count, 7)
        XCTAssertFalse(entries.contains("identity"))
        XCTAssertFalse(entries.contains(".env"))
        XCTAssertFalse(entries.contains("__pycache__"))
    }
}
