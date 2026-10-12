# 参与开发

先阅读 [快速开始](docs/快速开始.md)、[安全边界](SECURITY.md) 和 [发布与验收](docs/发布与验收.md)。当前只支持 macOS 客户端、常驻 Mac 与 Debian/Ubuntu VPS，不新增托管 Agent 或另一套模型配置系统。

开发前需要 Python 3.9+；Mac 构建还需要完整 Xcode 与 XcodeGen。Xcode 工程由 `macos/project.yml` 生成，不提交个人 Xcode 状态、构建缓存、连接配置、密钥或日志。

```bash
bash scripts/check.sh
bash scripts/check.sh --macos
docker build -t hermland-ssh-test -f tests/ssh/Dockerfile tests/ssh
docker run --rm -v "$PWD:/src:ro" hermland-ssh-test
```

真实 SSH 检查必须在独立容器中运行，禁止直接在真实 VPS 执行 `tests/onboarding-linux-check.sh`。它会创建和撤销测试账户，修改容器里的 SSH 配置。它不发送模型消息，也不读取用户的真实私钥。

提交 PR 时说明目标、改动范围、执行过的检查以及未验证项。新增安全行为应有能重现问题的必要测试。不要为了简化配置关闭认证、放宽端口范围或自动批准设备；不要用 HTTP 200 代替登录、模型或使用验收。

项目使用 MIT。上游 Hermes、Hermes WebUI、OpenClaw 和系统工具仍遵循各自许可证；本仓库不打包或重许可它们。
