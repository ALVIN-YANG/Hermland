import Foundation

enum SetupPurpose: String, CaseIterable, Identifiable {
    case firstSetup, additionalDevice
    var id: String { rawValue }
    var title: String { self == .firstSetup ? "第一次配置" : "新增一台电脑" }
}

enum OnboardingInstructions {
    static let repository = URL(string: "https://github.com/ALVIN-YANG/Hermland")!

    static func prompt(for backend: AgentBackend) -> String {
        let adapter =
            backend == .openclaw
            ? "已有 OpenClaw：复用 Gateway 与 Control UI，不安装 Hermes。check、relay-install、export 都加 --backend openclaw；按实际 gateway.port 和 controlUi.basePath 配置，保留 token/password 与设备身份校验。"
            : "已有 Hermes：复用 Hermes 与 WebUI。若仅缺 WebUI，只补 WebUI，不安装第二套 Agent，不改模型配置。"
        return """
            我已经在使用你，请协助配置 Hermland 远程接入。项目：\(repository.absoluteString)。可以使用我从 App 导出并解压的 HermlandSetup 工具包，或取得项目源码；先读 docs/快速开始.md，不执行未知的一行下载脚本。
            \(adapter)
            先确认 Agent 的实际运行主机为常驻 macOS、VPS 为 Debian/Ubuntu，且已有我核对过的管理员 SSH；不满足就停下说明限制。复用我的 Agent、模型、凭据、记忆与会话，不重装、不升级、不迁移、不读取或输出凭据。按 deploy 脚本逐步执行，每一步报告 PASS/FAIL；失败停在当前步骤，不跳过检查。
            常驻机和客户端公钥由我手动提供并核对指纹。每次授权前必须获得我对这台机器的明确确认，不能主动申请或自动审批。没有 VPS 执行权限就给我管理命令，不复制管理私钥、不获取永久管理权限。服务器公钥只从已有可信管理连接或控制台获取，不盲信 ssh-keyscan。
            不公开 WebUI，不扩大监听，不关闭 SSH 主机身份校验、Gateway 认证或安全审批。发现不兼容的 SSH Match 规则时停下，不删除或重排其他用户的策略。最后导出已授权设备的连接 JSON，让我导入 App。链路健康、网页登录、真实模型回答分别验收；模型测试由我本人发送。不要仅凭健康检查声称全部完成。
            给我看的进度请说清「在哪台机器操作、当前结果、需要我做什么」。授权前显示设备名和公钥 SHA256 指纹，等我单独确认；不是只回复“已成功”。完成后返回可保存的 .json 连接文件，并同时报告本机设备公钥指纹与 VPS 服务器指纹，供我分别核对。没有执行权限或可信管理连接时，停在该步给手动命令，不虚构文件或检查结果。
            """
    }

    /// Only public material crosses the clipboard. Copying this is not authorization.
    static func request(
        for backend: AgentBackend, purpose: SetupPurpose, publicKey: String,
        server: SetupServerDetails? = nil
    ) throws -> String {
        let key = try SSHConfiguration.normalizedPublicKey(publicKey)
        guard let fingerprint = SSHConfiguration.fingerprint(key) else {
            throw SSHConnectionError.process("设备公钥不可用，未复制配置材料。")
        }
        let scope =
            purpose == .firstSetup
            ? "任务：首次配置。先检查并复用已有服务和隧道，只补缺失的组件；常驻机公钥另由我手动提供并确认。"
            : "任务：新增一台电脑。只检查已有中转、人工授权下面的客户端公钥并导出配置；不要安装、升级或重建后端、VPS 工具或常驻机隧道。已有中转不通时停下报告，不自动修复。"
        let serverContext = purpose == .firstSetup ? try server?.instructionContext() ?? "" : ""
        return """
            \(scope)
            \(serverContext)
            客户端类型：\(backend.title)
            本次手动发送的客户端公钥：
            \(key)
            公钥指纹：\(fingerprint)
            这份材料不是授权。我会在你报告指纹与要授权的机器后，另行明确确认。

            \(prompt(for: backend))
            """
    }
}

enum SetupResources {
    static func guide(in bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: "快速开始", withExtension: "md") else {
            throw SSHConnectionError.process("配置指引资源缺失，请重新构建或使用仓库 docs/快速开始.md。")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func export(to destination: URL, bundle: Bundle = .main) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else {
            throw SSHConnectionError.process("目标文件已存在。请用新文件名导出，不覆盖旧工具包。")
        }
        let temporary = try SSHIdentity.privateTemporaryDirectory()
        defer { try? files.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("HermlandSetup", isDirectory: true)
        let deploy = root.appendingPathComponent("deploy", isDirectory: true)
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        try files.createDirectory(at: deploy, withIntermediateDirectories: true)
        try files.createDirectory(at: docs, withIntermediateDirectories: true)
        guard let resources = bundle.resourceURL else {
            throw SSHConnectionError.process("配置工具资源缺失，请重新构建 App。")
        }
        for name in [
            "hermland.py", "ssh_policy.py", "setup-vps.sh", "ssh-device.sh", "ssh-relay.sh",
            "connection.example.json", "connection.openclaw.example.json",
        ] {
            try files.copyItem(at: resources.appendingPathComponent(name), to: deploy.appendingPathComponent(name))
        }
        for name in ["快速开始", "准备中转服务器", "安全门禁", "远程中转", "发布与验收", "外网连接方案对比", "外网连接方案对比.en"] {
            guard let source = bundle.url(forResource: name, withExtension: "md") else {
                throw SSHConnectionError.process("配置说明资源缺失，请重新构建 App。")
            }
            try files.copyItem(at: source, to: docs.appendingPathComponent(name + ".md"))
        }
        for name in ["README.md", "README.en.md", "LICENSE", "SECURITY.md", "CONTRIBUTING.md"] {
            guard let source = bundle.resourceURL?.appendingPathComponent(name), files.fileExists(atPath: source.path)
            else {
                throw SSHConnectionError.process("工具包说明或许可证缺失，请重新构建 App。")
            }
            try files.copyItem(at: source, to: root.appendingPathComponent(name))
        }
        let artwork = root.appendingPathComponent("assets/readme", isDirectory: true)
        try files.createDirectory(at: artwork, withIntermediateDirectories: true)
        for name in ["panorama.png", "how-it-works.svg", "how-it-works.en.svg", "welcome-0.2.0.png", "server-setup-0.2.0.png"] {
            try files.copyItem(at: resources.appendingPathComponent(name), to: artwork.appendingPathComponent(name))
        }
        // ditto writes only our temporary archive; copyItem refuses a racing overwrite.
        let archive = temporary.appendingPathComponent("HermlandSetup.zip")
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        command.arguments = ["-c", "-k", "--keepParent", root.path, archive.path]
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        try command.run()
        command.waitUntilExit()
        guard command.terminationStatus == 0 else { throw SSHConnectionError.process("工具包导出失败。") }
        try files.copyItem(at: archive, to: destination)
    }
}
