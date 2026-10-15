import Foundation

/// Public setup notes, not a saved route or evidence of a successful SSH login.
struct SetupServerDetails: Equatable {
    var host = ""
    var port = "22"
    var administratorReady = false

    var isReady: Bool { (try? instructionContext()) != nil }

    func instructionContext() throws -> String {
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.count <= 253,
            address.range(of: #"\A[A-Za-z0-9][A-Za-z0-9.-]*\z"#, options: .regularExpression) != nil,
            let number = Int(port), (1...65535).contains(number), administratorReady
        else {
            throw InvalidDetails()
        }
        return """
            我提供的 VPS 地址：\(address)；SSH 端口：\(number)。
            我确认自己或管理员已核对服务器身份并可管理它；这是我的准备信息，不是 App 验证结果。请仍通过已有可信管理连接核对服务器公钥并逐步检查，不盲信扫描结果。不把这个地址用于跳过身份校验。
            """
    }

    private struct InvalidDetails: LocalizedError {
        var errorDescription: String? { "请填写不含账号或密码的服务器 IP／域名、有效端口，并确认已有可信管理登录。" }
    }
}

struct SetupContext: Equatable {
    var firstSetup = true
    var server = SetupServerDetails()
    var serverForRequest: SetupServerDetails? { firstSetup ? server : nil }
}
