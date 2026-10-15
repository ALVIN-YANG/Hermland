# Hermland

[简体中文](README.md) · [English](README.en.md)

**家里的 Hermes / OpenClaw，出门也能用。** 在另一台 Mac 打开 Hermland，接着用原来的 Agent。模型、记忆和会话留在家里，不用重新配置，也不用把 Agent 网页开放到公网。

[下载 Mac 版](https://github.com/ALVIN-YANG/Hermland/releases/download/v0.2.1/Hermland-0.2.1.zip) · [官网](https://alvin-yang.github.io/Hermland/) · [完整配置指南](docs/快速开始.md)

0.2.1 Beta · macOS 14+ · Apple Silicon / Intel 通用版 · 已签名、Apple 公证 · 免费、MIT 开源

![Hermland 原生欢迎页：选择已经在用的 Hermes 或 OpenClaw，开始连接；也可以直接导入已有连接文件。](assets/readme/welcome-0.2.0.png)

*原生欢迎界面预览。新版 VPS 与连接卡界面见[官网](https://alvin-yang.github.io/Hermland/#setup)。Hermland 是连接工具，不是另一个 Agent，也不是远程桌面。*

## 开始前，你需要什么

- **家里的 Mac：运行 Agent。** 已有 Hermes + WebUI，或 OpenClaw Gateway + Control UI，保持联网、用户登录、不睡眠。原来的模型密钥不用发给 Hermland。
- **自己的云服务器（VPS）：转接连接。** 使用 Debian / Ubuntu，由你或可信管理员管理。无需域名，不用给家里路由器开入站端口。
- **外出的 Mac：打开 Hermland。** macOS 14 或更新版本，只安装这个 App，不用再装一份 Agent。

**还没有 VPS？** 它是一台向云厂商租用的服务器，需你自行购买和维护。先按[服务器准备指南](docs/准备中转服务器.md)取得公网 IP、SSH 端口，并确认能可信登录，再回到 App。首次配置需要管理员权限，App 不是填一个 IP 就能自动开通的托管服务。

## 第一次连接，照着 App 做

### 1. 填服务器地址

在外出的 Mac 打开 Hermland，选择你已有的 Hermes / OpenClaw，点「开始连接」。填自己的 VPS 地址和 SSH 端口，确认你或管理员已核对服务器身份并能登录。

到这里，服务器应已准备好；**填地址不等于安装成功或已经连通**。还没有服务器，就选「还没有」查看准备指引。

### 2. 把连接卡发给原 Agent

点「复制连接卡」，回到你平时与 Hermes / OpenClaw 对话的入口，粘贴发送。卡片包含配置指令、本机公钥和指纹，不含私钥或密码。

有执行权限的 Agent 可以协助配置；没有权限，就由你或管理员按「查看手动方式」执行。**核对对方报告的设备名、公钥指纹，再明确同意授权**。指纹就是 App 显示的 `SHA256:…` 识别码，双方应一致；首次还需核对家里 Mac 的公钥。已有服务只复用，不重装 Agent、不改模型、不搬会话。

这一步的结果：Agent 或管理员发回一个 **`.json` 连接文件**。复制或发送连接卡，本身不代表已经授权。

### 3. 导入文件，开始使用

把连接文件保存到这台 Mac。点「我收到连接文件了」，选择它，核对可信来源和服务器指纹，再点「来源可信，连接并检查」。取消导入不会替换原配置。

四项检查通过后，完成原网页登录，发一条消息验证回答。**看到原会话、收到真实回答，才算完成。** 健康检查不会替你发送模型消息；OpenClaw 保留原来的 Gateway 登录与设备身份检查。

[我要自己配置：逐步命令与通过标准](docs/快速开始.md)

## 以后怎么用

- **日常打开：** App 用保存的配置自动连接，家里的 Mac 和 VPS 需保持在线。
- **新增电脑：** 选「其他设备已连好？新增这台 Mac」，只授权新公钥，不重新部署服务器。已有连接文件可直接导入；换电脑不复制旧私钥。
- **电脑丢失：** 管理员[撤销那台电脑的公钥](docs/安全门禁.md#撤销一台电脑)，已有连接会断开，并拒绝重连，不影响其他设备和聊天。当前管理用命令行，没有管理界面。

## 原理不复杂：多一条路，Agent 不搬家

![外出的 Mac 与家里的 Mac 各自主动通过 SSH 连接你的 VPS，消息双向传输。Agent 留在家里；VPS 管理员必须可信。](assets/readme/how-it-works.svg)

SSH 只负责传输，App 显示的仍是家里的 Agent 网页。两台 Mac 都主动连接 VPS，所以家里的路由器不必开放入站端口。

每台电脑有独立密钥，私钥留在本机钥匙串。管理员只登记你明确批准的公钥；App 也固定核对服务器公钥。**知道 IP、拿到公钥或连接文件，不等于能访问**，还须持有获准设备的私钥。设备账号只允许指定端口转发，不能执行 Shell。

边界也明确：**必须信任 VPS 管理员，两段 SSH 不是两台 Mac 之间的端到端加密。** 原 Agent 登录仍需保留，本机其他程序也能访问 App 已打开的本地端口。没有公网授权申请或自动批准。

[详细连接原理](docs/远程中转.md) · [设备授权与撤销](docs/安全门禁.md) · [安全边界与漏洞报告](SECURITY.md)

### 为什么不直接用 Tailscale / VPN？

Hermland 专门连接一个 Agent 网页，复用自己的 VPS 和 Mac 自带 SSH，不另加入 VPN 网络。代价是自己维护服务器，首次配置不一定比 Tailscale 简单，也不代表比它更安全。Tailscale 同样支持设备审批与访问限制，而且它的 [DERP 中转不能解密端到端加密流量](https://tailscale.com/docs/reference/derp-servers)；我们的 VPS 管理员必须可信。

已有 Tailscale、需要访问 NAS 或远程桌面等多个服务，可以继续用它。Hermland 不修改现有 VPN，当前也没有 Tailscale 模式。选型见[六种外网连接方案对比](docs/外网连接方案对比.md)。

<details>
<summary>展开功能全景图</summary>

![Hermland 功能概念图：复用已有 Agent，手动公钥授权，连接检查与设备撤销。不是软件截图。](assets/readme/panorama.png)

带小人的全景图保留为功能概念示意；实际操作以 App 和上面的流程为准。

</details>

## 获取 App

[下载 Hermland-0.2.1.zip](https://github.com/ALVIN-YANG/Hermland/releases/download/v0.2.1/Hermland-0.2.1.zip) → 解压 → 移到「应用程序」→ 打开。升级前先退出旧版。配置工具已内置，`HermlandSetup-0.2.1.zip` 只是可选独立工具包，不是第二个 App。

0.2.1 已通过 Developer ID 签名、Apple 公证、票据附加和最终 ZIP 解包后的 Gatekeeper 检查。[版本说明、SHA256 与构建来源](https://github.com/ALVIN-YANG/Hermland/releases/tag/v0.2.1)可供核对。首次“是否打开”是正常确认；钥匙串提示由你核对后处理，不删除设备密钥。若提示无法验证开发者，请核对来源和版本并反馈，**不要关闭 Gatekeeper 或运行去除保护的脚本**。见[苹果的安全打开说明](https://support.apple.com/zh-cn/102445)。

**当前仍是 Beta：** 独立新用户、Intel 实机和更多跨网络验收待完成，未声称通过独立安全审计。旧 `-dev` 包未公证，请选新版。OpenClaw 集成验收对应 2026.9.9，其他版本需实际验证。iOS [正在开发验收](ios/README.md)，尚未提交审核或开放下载；暂无 Windows 客户端、服务器代购或官方一行安装器。详见[发布与验收](docs/发布与验收.md)。

<details>
<summary>源码构建与参与开发</summary>

需要完整 Xcode、XcodeGen 和 Python 3.9+：

```bash
git clone https://github.com/ALVIN-YANG/Hermland.git
cd Hermland/macos
xcodegen generate
xcodebuild -project Hermland.xcodeproj -scheme Hermland -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build build
open .build/Build/Products/Debug/Hermland.app
```

项目根目录执行 `bash scripts/check.sh --macos`。测试、隔离 SSH 验收和打包约定见 [CONTRIBUTING](CONTRIBUTING.md)；不要在真实 VPS 上运行隔离容器测试。CI artifact 未公证，不等同于正式发行包。

反馈问题时使用 App 的脱敏报告，不上传密钥、令牌或聊天记录。项目代码与自有素材采用 [MIT](LICENSE)，上游保留各自许可证。

</details>
