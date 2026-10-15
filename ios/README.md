# Hermland iOS

状态：实现与验收中，未提交 App Store 审核，未开放下载。

首版沿用已有的 Hermes WebUI 或 OpenClaw Control UI。原生界面只负责配置核对、设备公钥分享、SSH 连接和状态显示；网页仍由原 Agent 提供。最低 iOS 17，支持 iPhone 和 iPad，免费、无内购。

使用流程：选择原 Agent → 准备自己的中转服务器 → 分享连接卡到原 Agent 对话并手动确认授权 → 导入返回的 JSON、核对服务器身份后连接。已有 Mac 中转时，从欢迎页选择新增这台设备，无需重装 Agent 或复制 Mac 私钥。已有 JSON 可以直接导入。界面与 Mac 共享轻盈信使插画、原生控件和连接原理说明；见 [首次连接界面](../docs/首次连接界面.md)。

首次打开可以选择「先看离线演示」。它明确显示示例状态与原生示例会话，不建立隧道、不调用模型、不更改配置，也不是原 WebUI 的复刻或真实连接验收。真实连接的公钥授权要求不变。

## 本地构建

需要 Xcode 26.3+、XcodeGen。依赖固定在根目录 `Package.resolved`。

```bash
bash scripts/check-ios.sh
```

真机测试需要自己的 Apple 开发者团队与已配对的设备。`project.yml` 中的团队是项目发布者的个人团队；其他开发者须替换为自己的团队，不需要项目发布者的证书或私钥。

```bash
xcodegen generate --spec ios/project.yml
```

再用 Xcode 打开生成的工程，选择自己的签名团队与真机。请勿把签名凭据提交到 Git。

## 安全边界

- Ed25519 私钥保存在本机钥匙串，`WhenUnlockedThisDeviceOnly`，不导出、不通过 iCloud 同步。不声称使用 Secure Enclave。
- 必须匹配配置中的完整 SSH 服务器公钥。没有密码回退、跳过校验或自动申请授权。
- 本地 HTTP 入口仅监听 `127.0.0.1`，不是公网服务。转发目标只能是配置中的远端 loopback 端口，最终权限由 VPS 的 SSH 策略限制。
- App 进入后台时结束前台隧道，回来后可恢复连接。恢复页面使用 GET，不自动重发聊天消息。
- WebKit 数据按连接隔离，保持原 Agent 认证。外部网页只在用户点击 HTTPS 链接时打开。
- 双 SSH 是分段加密，不是绕过 VPS 的端到端加密。VPS 管理员仍须可信。
- 移除本机配置不等于撤销服务器授权；丢失设备时由管理员撤销其公钥。

## 已有证据与剩余验收

2026-10-13：共享配置测试、模拟器钥匙串重载测试、macOS 原工程回归通过。独立 Docker OpenSSH 测试通过大响应、连续短连接、WebSocket、错误主机公钥、未授权密钥、端口限制与撤销授权。同源登录跳转通过，跨源跳转被拒绝。

真实上游隔离验收也已通过：Hermes WebUI `bfe40ffba8a09b6342189cd50c55535220a30d48` 的健康响应、登录页、未登录/错误密码拒绝、正确密码登录和会话列表读取；OpenClaw 2026.9.9 的 Control UI、JS 资源、无令牌/错误令牌/缺少设备身份拒绝，以及签名后的只读健康 RPC。它们经本项目的 SwiftNIO SSH 转发完成，未挂载用户配置、未安装 Hermes Agent、未调用模型。该证据不代替实际手机上的网页交互和模型回答验收。

尚待完成：iPhone 实际连接、网页登录及后台恢复、iPad 布局、发布签名包、公开隐私链接、商店真实截图、审核访问路径与 App Store Connect 必填项。必须完成这些项后再提交，不把安装成功或编译通过当成完整可用。

Apple 应用标识 `land.hermland.ios` 和 [App Store Connect 记录](https://appstoreconnect.apple.com/apps/6822241976/distribution)已创建，Apple App ID 为 `6822241976`。尚未上传或提交审核。

隔离 SSH 测试只使用新建的测试容器，不挂载任何用户配置：

```bash
docker build -t hermland-ssh-check:local -f tests/ssh/Dockerfile tests/ssh
HERMLAND_IOS_SSH_TEST=isolated swift test -j 4 --filter SSHIntegrationTests
```

图标沿用 Mac 端的「轻盈信使」，另有 iOS 全出血版本 `artwork/icons/hermland-icon-ios-1024.png`；未替换 Mac 图标。原始概念图不是商店截图。第三方许可证随 App 分发，见 [第三方组件](第三方组件.md)。
