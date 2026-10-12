import SwiftUI

struct ChatView: View {
    @ObservedObject var store: AppState

    var body: some View {
        NavigationSplitView {
            sessionList
        } detail: {
            conversation
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            List(store.sessions, selection: Binding(
                get: { store.selectedSessionID },
                set: { id in
                    guard let id else { return }
                    Task { await store.openSession(id) }
                }
            )) { session in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if !session.preview.isEmpty {
                        Text(session.preview)
                            .font(.system(size: 11))
                            .foregroundStyle(HermlandColor.secondary)
                            .lineLimit(2)
                    }
                }
                .tag(session.id)
                .padding(.vertical, 3)
            }
            .listStyle(.sidebar)

            HStack {
                Button("新对话") {
                    Task { await store.newChat() }
                }
                Spacer()
                Button("断开") {
                    store.disconnect()
                }
            }
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .safeAreaInset(edge: .top) {
            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            StatusDot(ok: store.isConnected)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.status?.summary ?? store.settings.displayURL)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Text("已登录 \(store.signedInAs)")
                    .font(.system(size: 10))
                    .foregroundStyle(HermlandColor.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(HermlandColor.sidebar)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if store.messages.isEmpty {
                            Text(store.selectedSessionID == nil ? "开一个新对话，或从左边点进旧会话。" : "这轮还没有消息。")
                                .foregroundStyle(HermlandColor.secondary)
                                .padding(.top, 40)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(store.messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if let banner = store.banner {
                Text(banner)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            composer
        }
        .background(HermlandColor.canvas)
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(label(for: message.role))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HermlandColor.tertiary)
                Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.role == .user ? HermlandColor.userBubble : HermlandColor.panel,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            }
            if message.role != .user { Spacer(minLength: 80) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $store.draft)
                .font(.system(size: 13))
                .frame(minHeight: 44, maxHeight: 120)
                .padding(6)
                .background(HermlandColor.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(HermlandColor.line.opacity(0.8), lineWidth: 1)
                }
            Button("发送") {
                Task { await store.send() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(store.isSending || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .controlSize(.large)
        }
        .padding(12)
    }

    private func label(for role: ChatMessage.Role) -> String {
        switch role {
        case .user: return "你"
        case .assistant: return "Hermes"
        case .system: return "系统"
        case .tool: return "工具"
        case .unknown: return ""
        }
    }
}
