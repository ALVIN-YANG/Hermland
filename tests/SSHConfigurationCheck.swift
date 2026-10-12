import Foundation

@main
enum SSHConfigurationCheck {
    static func main() throws {
        let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKnAc33IigsphK1ZXasje0U/gOKbBuiSO75mI0xGkVlZ"
        let valid = SSHConfiguration(host: "example.com", port: 22, user: "hl-device0001", remotePort: 19119, localPort: 19121, serverPublicKey: key)
        _ = try valid.validated()
        func rejected(_ change: (inout SSHConfiguration) -> Void) {
            var value = valid
            change(&value)
            do { _ = try value.validated(); fatalError("Unsafe configuration was accepted") } catch { }
        }
        rejected { $0.host = "-oProxyCommand=bad" }
        rejected { $0.host = "example.com\nmalicious" }
        rejected { $0.user = "root" }
        rejected { $0.user = "user@other" }
        rejected { $0.port = 0 }
        rejected { $0.localPort = 65536 }
        rejected { $0.serverPublicKey = key + "\n* " + key }
        rejected { $0.serverPublicKey = "SHA256:not-a-public-key" }
        let args = valid.sshArguments(identity: URL(fileURLWithPath: "/tmp/device-key"), knownHosts: URL(fileURLWithPath: "/tmp/pinned-hosts"))
        precondition(args.contains("StrictHostKeyChecking=yes"))
        precondition(args.contains("IdentityAgent=none"))
        precondition(args.contains("127.0.0.1:19121:127.0.0.1:19119"))
        var otherPort = valid
        otherPort.port = 2222
        precondition(otherPort.knownHostsEntry.hasPrefix("[example.com]:2222 "))
        print("SSH configuration security checks passed: validation, host pinning, loopback forwarding")
    }
}
