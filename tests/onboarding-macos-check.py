"""Native launchd smoke test. Uses an isolated directory, label and loopback port."""
import importlib.util
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

if sys.platform != "darwin" or os.getuid() == 0:
    raise SystemExit("请在 macOS 登录用户下运行")
spec = importlib.util.spec_from_file_location("hermland_setup", Path(__file__).parents[1] / "deploy/hermland.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

label = f"land.hermland.onboarding-check-{os.getpid()}"
target = f"gui/{os.getuid()}/{label}"
with tempfile.TemporaryDirectory(prefix="hermland-launchd-") as folder:
    directory = Path(folder)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        number = probe.getsockname()[1]
    server = """from http.server import BaseHTTPRequestHandler,HTTPServer
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(200); self.end_headers(); self.wfile.write(b'{"status":"ok"}')
 def log_message(self,*args): pass
HTTPServer(('127.0.0.1',%d),Handler).serve_forever()
""" % number
    value = setup.job(label, [sys.executable, "-c", server], directory)
    try:
        # Real launchctl; only the test's plist destination is isolated.
        with patch.object(setup.Path, "home", return_value=directory):
            setup.relay_key()
            identity = directory / "Library/Application Support/HermlandRelay/identity"
            original_key = identity.read_bytes()
            setup.relay_key()
            setup.require(identity.read_bytes() == original_key, "重复执行改变了中转私钥")
            setup.require(identity.stat().st_mode & 0o777 == 0o600, "私钥权限不是 600")
            setup.install_job(value)
            setup.install_job(value)
        for _ in range(10):
            if setup.listeners(number):
                break
            time.sleep(1)
        setup.check_listener(number)
        print("PASS：macOS 原生服务可重复登记，真实回环健康检查通过")
    except Exception:
        detail = subprocess.run(["/bin/launchctl", "print", target], capture_output=True, text=True)
        print(detail.stdout)
        for key in ("StandardOutPath", "StandardErrorPath"):
            path = Path(value[key])
            if path.exists():
                print(path.read_text()[-2000:])
        raise
    finally:
        result = subprocess.run(["/bin/launchctl", "bootout", target], capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"测试服务清理失败，请移除 {target}")
        for _ in range(10):
            if not setup.listeners(number):
                break
            time.sleep(0.2)
        setup.require(not setup.listeners(number), "测试端口在服务退出后仍监听")
        print("PASS：测试服务与端口已清理，没有改动现有 Hermland 服务")
