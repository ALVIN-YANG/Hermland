import Foundation

@MainActor
final class SSHTunnel {
    var onUnexpectedExit: (() -> Void)?
    private var process: Process?
    private var folder: URL?
    private var log = ""
    private var listening = false
    private var established = false

    func start(configuration: SSHConfiguration, identity: SSHIdentity) async throws -> URL {
        stop()
        let config = try configuration.validated()
        let folder = try SSHIdentity.privateTemporaryDirectory()
        self.folder = folder
        let privateKey = folder.appendingPathComponent("identity")
        let knownHosts = folder.appendingPathComponent("known_hosts")
        do {
            try identity.privateKey.write(to: privateKey)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKey.path)
            try config.knownHostsEntry.write(to: knownHosts, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHosts.path)
            let child = Process()
            // The supervisor also closes SSH and removes temporary private material if the App crashes.
            child.executableURL = URL(fileURLWithPath: "/bin/sh")
            child.arguments = ["-c", Self.supervisor, "hermland-ssh", String(ProcessInfo.processInfo.processIdentifier), folder.path] + config.sshArguments(identity: privateKey, knownHosts: knownHosts)
            child.standardInput = FileHandle.nullDevice
            child.standardOutput = FileHandle.nullDevice
            let pipe = Pipe()
            child.standardError = pipe
            self.process = child
            pipe.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; return }
                let message = String(decoding: data, as: UTF8.self)
                Task { @MainActor in
                    guard let self, let child, self.process === child else { return }
                    self.log = String((self.log + message).suffix(16_000))
                    if self.log.contains("Local forwarding listening on 127.0.0.1 port \(config.localPort)") {
                        self.listening = true
                    }
                }
            }
            child.terminationHandler = { [weak self] child in
                Task { @MainActor in
                    guard let self, self.process === child else { return }
                    let notify = self.established
                    self.process = nil
                    self.established = false
                    if notify { self.onUnexpectedExit?() }
                }
            }
            try child.run()
            for _ in 0..<200 {
                try Task.checkCancellation()
                guard child.isRunning, self.process === child else { throw failure() }
                if listening {
                    established = true
                    return config.localURL
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw SSHConnectionError.process("SSH 连接超时，请检查服务器地址和网络")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        established = false
        listening = false
        let child = process
        process = nil
        if let child, child.isRunning { child.terminate() }
        // A running supervisor owns cleanup. Never remove its identity while SSH is starting.
        if child == nil || child?.isRunning == false, let folder {
            try? FileManager.default.removeItem(at: folder)
        }
        folder = nil
        log = ""
    }

    private func failure() -> SSHConnectionError {
        if log.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") || log.contains("Host key verification failed") {
            return .process("服务器身份校验失败。请向管理员核对公钥，不能跳过校验")
        }
        if log.contains("Permission denied") { return .process("这台设备的公钥尚未授权，或已被撤销") }
        if log.contains("Address already in use") { return .process("本机端口已被占用，请关闭其他 Hermland 或更换本机端口") }
        return .process("SSH 连接失败，请检查服务器地址、端口和专用用户")
    }

    private static let supervisor = """
    parent_pid="$1"
    cleanup_dir="$2"
    shift 2
    ssh_pid=""
    cleanup() {
        if [ -n "$ssh_pid" ]; then
            kill "$ssh_pid" 2>/dev/null || :
            wait "$ssh_pid" 2>/dev/null || :
        fi
        /bin/rm -f "$cleanup_dir/identity" "$cleanup_dir/known_hosts"
        /bin/rmdir "$cleanup_dir" 2>/dev/null || :
    }
    trap cleanup EXIT
    trap 'exit 0' TERM INT HUP
    /usr/bin/ssh "$@" &
    ssh_pid=$!
    while kill -0 "$parent_pid" 2>/dev/null; do
        if ! kill -0 "$ssh_pid" 2>/dev/null; then
            wait "$ssh_pid"
            exit $?
        fi
        sleep 1
    done
    exit 0
    """
}
