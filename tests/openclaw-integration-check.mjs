// Run only from onboarding-linux-check.sh in a disposable container with real OpenClaw.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHash, generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

assert(process.env.HERMLAND_ONBOARDING_TEST === "isolated" && existsSync("/.dockerenv"));
const entry = process.env.OPENCLAW_ENTRY;
const sshDirectory = process.env.OPENCLAW_SSH_TEST_DIR;
assert(entry && sshDirectory);
const WebSocket = createRequire(entry)("ws");
const build = JSON.parse(readFileSync(join(entry, "..", "dist", "build-info.json")));
const token = randomBytes(32).toString("hex");
const state = mkdtempSync("/tmp/hermland-openclaw-check-");
const children = [];
let gateway;
let logs = "";

function start(command, args, env = process.env) {
  const child = spawn(command, args, { env, stdio: ["ignore", "pipe", "pipe"] });
  children.push(child);
  for (const stream of [child.stdout, child.stderr]) stream.on("data", data => { logs = (logs + data).slice(-20000); });
  return child;
}
async function stop(child) {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  await Promise.race([new Promise(resolve => child.once("exit", resolve)), delay(8000)]);
  if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
}
async function waitFor(check, description) {
  for (let i = 0; i < 250; i++) {
    if (gateway?.exitCode !== null) throw new Error("Gateway exited before " + description);
    try { if (await check()) return; } catch { }
    await delay(200);
  }
  throw new Error("Timeout: " + description);
}
function command(program, args) {
  const result = spawnSync(program, args, { encoding: "utf8" });
  assert.equal(result.status, 0, (result.stderr ?? "").replaceAll(token, "[test-secret]"));
}
async function connect(sharedSecret, hasDevice) {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const publicBytes = publicKey.export({ type: "spki", format: "der" }).subarray(-32);
  const deviceId = createHash("sha256").update(publicBytes).digest("hex");
  return new Promise((resolve, reject) => {
    const ws = new WebSocket("ws://127.0.0.1:19121", { origin: "http://127.0.0.1:19121" });
    const timeout = setTimeout(() => { ws.terminate(); reject(new Error("WebSocket handshake timed out")); }, 8000);
    ws.on("error", reject);
    ws.on("message", raw => {
      const message = JSON.parse(raw.toString());
      if (message.event === "connect.challenge") {
        const scopes = ["operator.read"];
        const { nonce, ts } = message.payload;
        const payload = ["v3", deviceId, "openclaw-control-ui", "webchat", "operator", scopes.join(","),
                         String(ts), sharedSecret ?? "", nonce, "web", ""].join("|");
        const params = { minProtocol: 4, maxProtocol: 4,
          client: { id: "openclaw-control-ui", version: build.version, buildId: build.buildId, platform: "web", mode: "webchat" },
          role: "operator", scopes, caps: [], auth: sharedSecret ? { token: sharedSecret } : {} };
        if (hasDevice) params.device = { id: deviceId, publicKey: publicBytes.toString("base64url"),
          signature: sign(null, Buffer.from(payload), privateKey).toString("base64url"), signedAt: ts, nonce };
        ws.send(JSON.stringify({ type: "req", id: "connect", method: "connect", params }));
      } else if (message.id === "connect") {
        if (!message.ok) {
          clearTimeout(timeout); ws.close(); resolve(message);
        } else {
          assert.equal(message.payload.type, "hello-ok");
          ws.send(JSON.stringify({ type: "req", id: "health", method: "health", params: {} }));
        }
      } else if (message.id === "health") {
        clearTimeout(timeout); ws.close(); resolve(message);
      }
    });
  });
}

try {
  for (const basePath of ["/", "/openclaw/"]) {
    const configPath = join(state, basePath === "/" ? "root.json" : "prefix.json");
    writeFileSync(configPath, JSON.stringify({ gateway: { mode: "local", bind: "loopback", port: 18789,
      auth: { mode: "token", token }, controlUi: { basePath: basePath === "/" ? "" : "/openclaw" } },
      agents: { defaults: { workspace: join(state, "workspace") } } }), { mode: 0o600 });
    gateway = start(process.execPath, [entry, "gateway", "run"], { ...process.env,
      PATH: "/usr/local/bin:" + process.env.PATH, OPENCLAW_STATE_DIR: state, OPENCLAW_CONFIG_PATH: configPath });
    await waitFor(async () => (await fetch("http://127.0.0.1:18789/healthz")).ok, "Gateway liveness");
    const sshOptions = ["-F", "/dev/null", "-N", "-T", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
      "-o", "IdentityAgent=none", "-o", "StrictHostKeyChecking=yes", "-o", "GlobalKnownHostsFile=/dev/null",
      "-o", `UserKnownHostsFile=${join(sshDirectory, "known_hosts")}`, "-o", "ExitOnForwardFailure=yes"];
    const relay = start("/usr/bin/ssh", [...sshOptions, "-i", join(sshDirectory, "relay"),
      "-R", "127.0.0.1:19119:127.0.0.1:18789", "hl-relay@127.0.0.1"]);
    const client = start("/usr/bin/ssh", [...sshOptions, "-i", join(sshDirectory, "device"),
      "-L", "127.0.0.1:19121:127.0.0.1:19119", "hl-device0001@127.0.0.1"]);
    await waitFor(async () => (await fetch("http://127.0.0.1:19121" + basePath)).ok, "Control UI through two SSH tunnels");
    command("python3", ["/opt/hermland/hermland.py", "check", "--backend", "openclaw", "--port", "19121", "--ui-path", basePath]);
    const output = join(state, basePath === "/" ? "connection-root.json" : "connection-prefix.json");
    command("python3", ["/opt/hermland/hermland.py", "export", "--backend", "openclaw", "--ui-path", basePath,
      "--device", "hl-device0001", "--host", "relay.example.com", "--output", output]);
    const exported = JSON.parse(readFileSync(output));
    assert.equal(exported.backend, "openclaw"); assert.equal(exported.controlUIPath, basePath);
    assert(!readFileSync(output, "utf8").includes(token));
    const html = await (await fetch("http://127.0.0.1:19121" + basePath)).text();
    assert(html.includes("<openclaw-app"));
    const asset = html.match(/src="([^"]+\.js)"/)[1];
    assert((await fetch(new URL(asset, "http://127.0.0.1:19121" + basePath))).ok);
    assert.equal((await connect(undefined, true)).ok, false, "Missing token accepted");
    assert.equal((await connect("wrong-secret", true)).ok, false, "Wrong token accepted");
    assert.equal((await connect(token, false)).ok, false, "Missing device identity accepted");
    const authenticated = await connect(token, true);
    assert.equal(authenticated.ok, true, "Signed Control UI could not call read-only health RPC: " + JSON.stringify(authenticated.error));
    console.log(`PASS：OpenClaw ${basePath} 实际页面/资源、双 SSH、无/错令牌拒绝、设备身份和健康 RPC；未调用模型`);
    await stop(client); await stop(relay); await stop(gateway);
  }
} catch (error) {
  console.error(logs.replaceAll(token, "[test-secret]"));
  throw error;
} finally {
  for (const child of children.reverse()) await stop(child);
}
