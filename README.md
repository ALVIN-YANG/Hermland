# Hermland

**在另一台 Mac 上，继续使用你自己的 Hermes 或 OpenClaw。** 模型、记忆和会话仍在原来的常驻 Mac 上，不用迁移，也不用把 WebUI 暴露到公网。

A macOS SSH client for your existing Hermes or OpenClaw. Keep your agent where it is.

<p align="center">
  <a href="assets/readme/panorama.png"><img src="assets/readme/panorama.png" width="100%" alt="Hermland 功能全景：保留原 Agent 与会话，双 SSH 通道连接自己的 VPS，管理员手动授权公钥，已有 Agent 协助初始化，导入配置后逐项检查，并能单独撤销一台设备。首次使用：初始化、发公钥、导入配置、连接验收。"></a>
</p>

*全景图是原理示意，不是产品截图。当前为 0.1.0 开发预览，尚无正式签名、公证的安装包。*

## 你能用它做什么

- **接着用原来的 Agent。** 展示 Hermes WebUI 或 OpenClaw Control UI，不另建模型配置、记忆库或聊天后端。
- **只让授权电脑接入。** 每台电脑独立公钥，私钥留在本机钥匙串；管理员人工确认，客户端固定校验服务器身份。没有共享 Gate 令牌或自动审批。
- **把配置过程交给已有 Agent。** App 可复制初始化指令、导出配置工具；每步有通过标准，也能按说明手动完成。
- **看得见哪里通过、哪里失败。** 配置、密钥、SSH、后端健康逐项检查，可复制脱敏报告。健康通过不代表已登录或模型能回答。
- **单独撤销一台电脑。** 管理员用命令行列出、授权、撤销公钥；撤销会关闭该设备的现有连接并拒绝重连，不动其他设备和 Agent。

适合已经有 Hermes + WebUI 或 OpenClaw Gateway + Control UI 的用户。需要 macOS 14+ 客户端、一台在线且不睡眠的常驻 Mac，以及自己的 Debian/Ubuntu VPS。不是云托管 Agent，也不是远程桌面。

## 第一次怎么用

1. **初始化：** 在 App 选择 Hermes 或 OpenClaw，把「初始化指令」发给你平时使用的那个 Agent。它没有执行权限时，按「手动步骤」完成。
2. **发公钥：** 点「复制设备公钥」，通过可信渠道交给管理员。由你确认这台电脑，管理员才授权；不发送私钥。
3. **导入配置：** 管理员返回连接 JSON，App 导入后核对来源。文件包含服务器身份，不含密码、私钥或模型 API Key。
4. **连接验收：** 看四项连接检查，完成原网页登录，再由你发送一条消息确认模型回答。下次打开 App 会自动连接。

完整指令、管理员命令、每步通过标准见 **[快速开始](docs/快速开始.md)**。已有正确服务和隧道就复用，不重装 Agent，不改模型，不复制会话。

## 连接为什么可信

客户端和常驻 Mac 各自通过 SSH 接到你的 VPS；VPS 中转端口只在本机监听，不要求域名。客户端设备账户只能转发到指定端口，不能执行 Shell。管理员在家里的 Mini 或其他有管理权限的电脑上操作即可，当前没有管理 GUI。

双 SSH **不是客户端到常驻 Mac 的端到端加密**，VPS 管理员必须可信；客户端本机的其他程序也能访问已打开的回环端口。OpenClaw 原有登录与设备身份仍保留。工具只支持可验证的 SSH 规则，遇到通配符、地址条件或可能重叠的账户策略会停止，不改其他服务来凑成功。

[中转原理](docs/远程中转.md) · [公钥授权与撤销](docs/安全门禁.md) · [安全边界与私密漏洞报告](SECURITY.md)

## 获取 App

还没有可直接推荐给普通用户的正式 Release。开发者可从源码构建；需要完整 Xcode、XcodeGen 和 Python 3.9+，不要关闭 Gatekeeper 或钥匙串保护来运行开发包。

```bash
git clone https://github.com/ALVIN-YANG/Hermland.git
cd Hermland/macos
xcodegen generate
xcodebuild -project Hermland.xcodeproj -scheme Hermland -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build build
open .build/Build/Products/Debug/Hermland.app
```

[GitHub CI](https://github.com/ALVIN-YANG/Hermland/actions/workflows/ci.yml) 覆盖秘密扫描、Python 检查、Ubuntu/Debian 真 SSH 授权与撤销、macOS 测试和 Intel/Apple Silicon 通用开发包。CI artifact 未公证，不等同于正式发行。

OpenClaw 集成验收脚本对应 2026.9.9，其他上游版本仍需实际验收。当前没有 iOS/Windows 客户端、官方“一行下载”安装器或服务器购买服务。正式签名、公证和独立用户跨网络验收见 [发布与验收](docs/发布与验收.md)。

## 参与开发

在项目根目录执行 `bash scripts/check.sh --macos`；真实 SSH 容器检查、开发打包与贡献约定见 [CONTRIBUTING](CONTRIBUTING.md)。不要在真实 VPS 上运行隔离容器测试脚本。问题反馈使用 App 的脱敏检查报告，不上传密钥、令牌或聊天记录。

项目代码与自有素材采用 [MIT](LICENSE)，上游软件保留各自许可证。
