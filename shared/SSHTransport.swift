import Foundation
import NIOCore
import NIOSSH
import NIOTransportServices

/// One foreground connection. It can forward only the route the user reviewed.
@MainActor
public final class SSHTransport {
    private let group = NIOTSEventLoopGroup(loopCount: 1)
    private var remote: Channel?
    private var listener: Channel?
    private var closed = false
    public var onDisconnect: (() -> Void)?

    public init() {}

    public func start(configuration: SSHConfiguration, identity: DeviceIdentity) async throws -> URL {
        let config = try configuration.validated()
        guard remote == nil, !closed else { throw SSHConnectionError.process("连接已结束，请重试。") }
        let expected = try NIOSSHPublicKey(openSSHPublicKey: config.serverPublicKey)
        let ready = group.next().makePromise(of: Void.self)
        let host = PinnedHostKey(expected: expected)
        do {
            let channel = try await NIOTSConnectionBootstrap(group: group)
                .connectTimeout(.seconds(8))
                .channelInitializer { channel in
                    return channel.eventLoop.makeCompletedFuture {
                        let auth = DeviceAuthentication(username: config.user, identity: identity)
                        try channel.pipeline.syncOperations.addHandler(
                            NIOSSHHandler(role: .client(.init(userAuthDelegate: auth, serverAuthDelegate: host)),
                                          allocator: channel.allocator, inboundChildChannelInitializer: nil))
                        try channel.pipeline.syncOperations.addHandler(AuthenticationCompletion(ready: ready))
                    }
                }.connect(host: config.host, port: config.port).get()
            remote = channel
            try ensureActive()
            try await ready.futureResult.get()
            try ensureActive()
            // No listener exists until host identity and device authentication have succeeded.
            let server = try await NIOTSListenerBootstrap(group: group)
                .bindTimeout(.seconds(5))
                .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                .childChannelInitializer { inbound in
                    channel.eventLoop.flatSubmit {
                        let promise = channel.eventLoop.makePromise(of: Channel.self)
                        do {
                            let ssh = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                            let origin = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
                            ssh.createChannel(promise, channelType: .directTCPIP(.init(
                                targetHost: "127.0.0.1", targetPort: config.remotePort, originatorAddress: origin
                            ))) { child, type in
                                guard case .directTCPIP = type else {
                                    return child.eventLoop.makeFailedFuture(SSHConnectionError.process("转发类型被拒绝。"))
                                }
                                let (left, right) = ByteRelay.pair()
                                return child.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                                    .flatMap { child.pipeline.addHandlers([SSHBytes(), left]) }
                                    .flatMap { inbound.pipeline.addHandler(right) }
                            }
                        } catch { promise.fail(error) }
                        return promise.futureResult.map { _ in () }
                    }
                }.bind(host: "127.0.0.1", port: config.localPort).get()
            listener = server
            try ensureActive()
            channel.closeFuture.whenComplete { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.closed else { return }
                    self.close()
                    self.onDisconnect?()
                }
            }
            return config.localURL
        } catch {
            close()
            if let known = error as? SSHConnectionError { throw known }
            if error is CancellationError { throw error }
            throw SSHConnectionError.process("SSH 连接失败。请核对网络、设备授权和连接配置。")
        }
    }

    private func ensureActive() throws {
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
    }

    public func close() {
        closed = true
        listener?.close(promise: nil)
        remote?.close(promise: nil)
        listener = nil
        remote = nil
    }

    deinit {
        listener?.close(promise: nil)
        remote?.close(promise: nil)
        group.shutdownGracefully { _ in }
    }
}

final class PinnedHostKey: NIOSSHClientServerAuthenticationDelegate, Sendable {
    let expected: NIOSSHPublicKey
    init(expected: NIOSSHPublicKey) { self.expected = expected }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        if hostKey == expected { validationCompletePromise.succeed(()) }
        else { validationCompletePromise.fail(SSHConnectionError.process("服务器身份不一致。请让管理员核对公钥，不能跳过校验。")) }
    }
}

/// NIOSSH invokes the delegate on its connection event loop.
private final class DeviceAuthentication: NIOSSHClientUserAuthenticationDelegate {
    let username: String
    let key: NIOSSHPrivateKey
    private var attempted = false
    init(username: String, identity: DeviceIdentity) {
        self.username = username
        key = NIOSSHPrivateKey(ed25519Key: identity.key)
    }
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard !attempted, availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(SSHConnectionError.process("这台 iPhone 尚未授权，或授权已被撤销。"))
            return
        }
        attempted = true
        nextChallengePromise.succeed(.init(username: username, serviceName: "ssh-connection",
                                           offer: .privateKey(.init(privateKey: key))))
    }
}

private final class AuthenticationCompletion: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let ready: EventLoopPromise<Void>
    var completed = false
    var timeout: Scheduled<Void>?
    init(ready: EventLoopPromise<Void>) { self.ready = ready }
    func handlerAdded(context: ChannelHandlerContext) {
        timeout = context.eventLoop.scheduleTask(in: .seconds(12)) { [weak self] in
            self?.finish(.failure(SSHConnectionError.process("SSH 身份检查超时。")))
            context.close(promise: nil)
        }
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent { finish(.success(())) }
        context.fireUserInboundEventTriggered(event)
    }
    func channelInactive(context: ChannelHandlerContext) {
        finish(.failure(SSHConnectionError.process("SSH 在身份检查期间断开。")))
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        finish(.failure(error))
        context.close(promise: nil)
    }
    func handlerRemoved(context: ChannelHandlerContext) { timeout?.cancel() }
    private func finish(_ result: Result<Void, Error>) {
        guard !completed else { return }
        completed = true
        timeout?.cancel()
        ready.completeWith(result)
    }
}

private final class SSHBytes: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard message.type == .channel, case .byteBuffer(let bytes) = message.data else {
            context.close(promise: nil)
            return
        }
        context.fireChannelRead(wrapInboundOut(bytes))
    }
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(wrapOutboundOut(.init(type: .channel, data: .byteBuffer(unwrapOutboundIn(data)))), promise: promise)
    }
}

/// Byte-transparent relay with backpressure and half-close support; no HTTP retries or message replay.
private final class ByteRelay: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundIn = ByteBuffer
    private weak var partner: ByteRelay?
    private var context: ChannelHandlerContext?
    private var waitingToRead = false
    private var inputEnded = false
    private var outputEnding = false
    private var outputEnded = false

    static func pair() -> (ByteRelay, ByteRelay) {
        let left = ByteRelay(), right = ByteRelay()
        left.partner = right
        right.partner = left
        return (left, right)
    }
    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        partner?.resumeRead()
    }
    func handlerRemoved(context: ChannelHandlerContext) { self.context = nil }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        partner?.context?.write(data, promise: nil)
    }
    func channelReadComplete(context: ChannelHandlerContext) { partner?.context?.flush() }
    func channelInactive(context: ChannelHandlerContext) {
        // NWConnection.cancel() can discard writes already flushed but not processed yet.
        // Deliver queued bytes and a FIN; the peer can then close its input normally.
        partner?.finishOutput()
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            inputEnded = true
            partner?.finishOutput()
            closeIfFinished()
        } else { context.fireUserInboundEventTriggered(event) }
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        partner?.context?.close(promise: nil)
        context.close(promise: nil)
    }
    func read(context: ChannelHandlerContext) {
        if partner?.context?.channel.isWritable == true { context.read() }
        else { waitingToRead = true }
    }
    func channelWritabilityChanged(context: ChannelHandlerContext) { partner?.resumeRead() }
    private func resumeRead() {
        if waitingToRead, partner?.context?.channel.isWritable == true {
            waitingToRead = false
            context?.read()
        }
    }
    private func finishOutput() {
        guard !outputEnding, let context, context.channel.isActive else { return }
        outputEnding = true
        context.flush()
        let finished = context.eventLoop.makePromise(of: Void.self)
        context.close(mode: .output, promise: finished)
        finished.futureResult.whenComplete { [weak self] _ in
            self?.outputEnded = true
            self?.closeIfFinished()
        }
    }
    private func closeIfFinished() {
        if inputEnded && outputEnded { context?.close(promise: nil) }
    }
}
