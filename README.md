# Hermland

Private remote access to your existing Hermes or OpenClaw — without moving your agent.

Hermland 是 macOS 远程客户端。Agent、模型、记忆和会话仍在你自己的常驻 Mac 上；客户端只建立可信连接并展示原有界面。

当前是 **0.1.0 开发预览**，不是已完成的公共 Beta。没有 Developer ID 签名/公证发行包，独立用户与跨网络验收仍待完成。MIT 开源，不要求域名，不直接公开 WebUI，不提供共享访问令牌。

## 适合谁

你已经在使用 Hermes + Hermes WebUI，或 OpenClaw Gateway + Control UI；希望从另一台 Mac 接着使用原来的 Agent，且愿意管理自己的 Debian/Ubuntu VPS。

当前支持 macOS 14+ 客户端、常驻 macOS、Debian/Ubuntu 的 SSH 服务。不是云托管 Agent、远程桌面或新的聊天后端，也不负责购买服务器、配置模型和复制 API Key。

## 四步接入

1. 选择已有 Agent，复制初始化指令发给它；可从 App 导出配置工具包，没有执行权限时使用手动步骤。
2. 复制这台电脑的设备公钥，通过可信渠道发送给管理员；每台电脑都由你人工确认。
3. 导入管理员返回的连接 JSON，核对服务器身份来源。
4. 连接并查看实际检查结果；在原网页完成登录，由你发送一条消息验收模型。

完整的 Agent 指令、六步手动流程和每步通过标准见 [快速开始](docs/快速开始.md)。App 可以复制不含地址、密钥、令牌或聊天的检查报告；配置工具包只含脚本、示例和说明。

## 原理与安全边界

客户端和常驻 Mac 分别通过 SSH 接到你自己的 VPS，中转只监听回环地址。每台客户端有独立 Ed25519 密钥，私钥放在本机钥匙串；管理员手动授权、列出与撤销公钥。服务器身份来自已核对的管理连接，不盲信首次访问。

两段 SSH **不是客户端到常驻 Mac 的端到端加密**；VPS 管理员必须可信。本机其他程序也能访问打开的回环端口。OpenClaw 原有 Gateway 登录和设备身份保留，不把健康检查当成已登录或模型可用。

安装工具会拒绝未经支持的自定义 SSH 条件规则，不自动改写其他账户策略。见 [安全说明](SECURITY.md)、[设备管理](docs/安全门禁.md) 和 [中转原理](docs/远程中转.md)。

## 开发与检查

需要完整 Xcode、XcodeGen 和 Python 3.9+。工程由配置生成，构建缓存与个人 Xcode 状态不纳入 Git。

```bash
git clone https://github.com/ALVIN-YANG/Hermland.git
cd Hermland
bash scripts/check.sh --macos
cd macos
xcodegen generate
xcodebuild -project Hermland.xcodeproj -scheme Hermland -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build build
open .build/Build/Products/Debug/Hermland.app
```

Python 合约检查：`bash scripts/check.sh`。真实 SSH 验收在隔离容器中运行，覆盖错误密钥、禁 Shell、受限转发、条件规则冲突与撤销；禁止在真实 VPS 上直接运行容器测试脚本。具体命令见 [参与开发](CONTRIBUTING.md)。

OpenClaw 集成脚本验证版本为 2026.9.9，可设置 `OPENCLAW_ENTRY` 在隔离容器内验证真实 Gateway、双 SSH、登录拒绝与只读健康 RPC；不发送模型消息。其他上游版本不能只凭测试文件声称兼容。

## 打包与发行

```bash
bash scripts/package-macos.sh --development
```

生成 Apple Silicon / Intel 通用开发包、配置工具包和校验值。开发包为临时签名且未公证，不能当作普通用户可直接安装的正式包；不要关闭系统安全保护来运行它。

正式打包入口会检查 Developer ID、Hardened Runtime、Apple 公证和 Gatekeeper。没有这些条件会停止，不静默降级。流程及独立用户验收清单见 [发布与验收](docs/发布与验收.md)。

## 项目范围

复用两个上游的原生页面与认证，不重做聊天、模型配置、Agent 市场或编排系统。当前没有管理 GUI、iOS/Windows 客户端或官方“一行下载”安装器。

问题反馈请提供脱敏的检查结果；漏洞使用 [私密报告](SECURITY.md)。Hermland 代码与项目自有素材采用 [MIT](LICENSE)，上游软件保留各自许可证。
