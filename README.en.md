# Hermland

[English](README.en.md) · [简体中文](README.md)

**Use your own Hermes or OpenClaw from another Mac.** Your models, memory, and conversations stay on the original always-on Mac. No migration, and no public WebUI endpoint.

<p align="center">
  <a href="assets/readme/panorama.png"><img src="assets/readme/panorama.png" width="100%" alt="Hermland overview: keep your existing agent and conversations, connect through two SSH tunnels via your own VPS, authorize device public keys manually, let your existing agent help with setup, import and check the connection, and revoke one device independently. Getting started: initialize, share a public key, import configuration, then verify the connection."></a>
</p>

*The illustration has Chinese labels and shows concepts, not a product screenshot. Version 0.1.0 is a development preview. A Developer ID–signed and notarized release is not available yet.*

## What you can do

- **Keep using your existing agent.** Hermland displays Hermes WebUI or OpenClaw Control UI. It does not create another model configuration, memory store, or chat backend.
- **Allow only authorized computers.** Each device has its own key pair. Private keys stay in the local macOS Keychain. An administrator approves public keys manually, and the client verifies the pinned server key. There is no shared Gate token or automatic approval.
- **Ask your existing agent to help with setup.** The app can copy setup instructions and export a configuration toolkit. Each step has a pass criterion; you can also follow the manual guide.
- **See which checks pass or fail.** Check configuration, device keys, SSH, and backend health separately, then copy a redacted report. A healthy endpoint does not prove that you are logged in or that the model can answer.
- **Revoke one computer.** The administrator lists, authorizes, and revokes public keys from the command line. Revocation closes that device's active connections and blocks reconnection without changing the agent or other devices.

For users who already run Hermes with WebUI, or OpenClaw Gateway with Control UI. You need a macOS 14+ client, an always-on Mac that stays online and awake, and your own Debian/Ubuntu VPS. Hermland is not hosted agent infrastructure or remote desktop software.

## Get started

1. **Initialize.** Choose Hermes or OpenClaw in the app, then send the initialization instructions to the agent you already use. If it cannot execute commands, follow the manual steps.
2. **Share a public key.** Copy the device public key and send it to your administrator through a trusted channel. Confirm the computer before it is authorized. Never send the private key.
3. **Import configuration.** Import the connection JSON returned by the administrator and verify its source. It includes the server identity, not passwords, private keys, or model API keys.
4. **Verify the connection.** Review the four checks, complete the original web login, then send a message yourself to test a real model response. The app reconnects automatically on later launches.

See the **[quick start guide (Chinese)](docs/快速开始.md)** for setup instructions, administrator commands, and pass criteria. Reuse working services and tunnels. Do not reinstall the agent, change models, or copy conversations. The app UI and detailed guides currently use Chinese.

## How access is controlled

The client and the always-on Mac each connect to your VPS over SSH. The relay port listens only on the VPS loopback interface; no domain name is required. Client device accounts can forward traffic only to the assigned port and cannot execute shell commands. Manage access from your home Mini or another computer with administrator SSH access. There is no management GUI yet.

Two SSH tunnels **do not provide end-to-end encryption between the client and the always-on Mac**: you must trust the VPS administrator. Other programs on the client computer can also access its open loopback port. OpenClaw's original login and device authentication remain in place. The tools stop on unsupported wildcard rules, address conditions, or potentially overlapping SSH policies; they do not rewrite other services to make setup succeed.

[Relay architecture (Chinese)](docs/远程中转.md) · [Authorize and revoke devices (Chinese)](docs/安全门禁.md) · [Security boundaries and private reports (Chinese)](SECURITY.md)

## Build the app

There is no official release ready for general installation yet. Developers can build from source with full Xcode, XcodeGen, and Python 3.9+. Do not disable Gatekeeper or Keychain protection to run a development build.

```bash
git clone https://github.com/ALVIN-YANG/Hermland.git
cd Hermland/macos
xcodegen generate
xcodebuild -project Hermland.xcodeproj -scheme Hermland -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath .build build
open .build/Build/Products/Debug/Hermland.app
```

[GitHub CI](https://github.com/ALVIN-YANG/Hermland/actions/workflows/ci.yml) covers secret scanning, Python checks, real SSH authorization and revocation on Ubuntu/Debian, macOS tests, and universal Intel/Apple Silicon development packages. CI artifacts are not notarized and are not official releases.

The OpenClaw integration acceptance script targets version 2026.9.9. Other upstream versions still need real verification. There are no iOS/Windows clients, official one-line download installer, or server purchasing service. See the [release and acceptance checklist (Chinese)](docs/发布与验收.md) for signing, notarization, and independent cross-network installation tests.

## Contribute

Run `bash scripts/check.sh --macos` from the repository root. Container-based SSH checks, development packaging, and contribution rules are in [CONTRIBUTING (Chinese)](CONTRIBUTING.md). Never run the isolated-container test script directly on a real VPS. Use the app's redacted diagnostic report for issues; do not upload keys, tokens, or conversations.

Project code and original assets use the [MIT License](LICENSE). Upstream projects retain their own licenses.
