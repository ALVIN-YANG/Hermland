"""Only contracts that protect onboarding: keys, pinning, conflicts and health checks."""
import argparse
import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("hermland_setup", Path(__file__).parents[1] / "deploy/hermland.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class OnboardingTests(unittest.TestCase):
    def test_key_contract_matches_app_and_rejects_injected_lines(self):
        raw = struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32) + bytes(range(32))
        key = "ssh-ed25519 " + base64.b64encode(raw).decode()
        self.assertEqual(setup.public_key(key + " device\n"), key)
        for invalid in (key + "\n" + key, key.replace("ssh-ed25519 ", "ssh-rsa ", 1),
                        "ssh-ed25519 SHA256:xyz", "ssh-ed25519 " + base64.b64encode(raw[:-1]).decode()):
            with self.assertRaises(setup.SetupError):
                setup.public_key(invalid)

    def test_relay_is_pinned_and_cannot_bind_public_interfaces(self):
        args = argparse.Namespace(host="relay.example.com", ssh_port=2222, relay_port=19119, backend_port=8787)
        command = setup.relay_arguments(args, Path("/private/identity"), Path("/private/a & b/known_hosts"))
        for option in ("StrictHostKeyChecking=yes", "IdentitiesOnly=yes", "IdentityAgent=none", "BatchMode=yes",
                       "ExitOnForwardFailure=yes", "ControlPath=none", "GlobalKnownHostsFile=/dev/null"):
            self.assertIn(option, command)
        self.assertEqual(command[command.index("-R") + 1], "127.0.0.1:19119:127.0.0.1:8787")
        self.assertEqual(command[-1], "hl-relay@relay.example.com")
        self.assertIn('UserKnownHostsFile="/private/a & b/known_hosts"', command)

    def test_existing_configuration_is_never_overwritten(self):
        with tempfile.TemporaryDirectory(prefix="hermland-unit-") as folder:
            path = Path(folder) / "connection.json"
            setup.save_new_or_same(path, b"original")
            setup.save_new_or_same(path, b"original")
            with self.assertRaises(setup.SetupError):
                setup.save_new_or_same(path, b"different")
            self.assertEqual(path.read_bytes(), b"original")
            linked = Path(folder) / "link"
            linked.symlink_to(path)
            with self.assertRaises(setup.SetupError):
                setup.save_new_or_same(linked, b"original")

    def test_check_rejects_public_listener_even_when_loopback_also_exists(self):
        with patch.object(setup, "listeners", return_value=["127.0.0.1:8787", "*:8787"]), \
             patch.object(setup, "health") as health:
            with self.assertRaises(setup.SetupError):
                setup.check_listener(8787)
            health.assert_not_called()

    def test_launchd_stays_foreground_and_roundtrips_paths_with_spaces(self):
        value = setup.job("land.hermland.test", ["/usr/bin/ssh", "-N", "-T"], Path("/tmp/a & b"))
        decoded = plistlib.loads(plistlib.dumps(value))
        self.assertEqual(decoded, value)
        self.assertTrue(decoded["KeepAlive"])
        self.assertIn("-N", decoded["ProgramArguments"])
        self.assertNotIn("-f", decoded["ProgramArguments"])
        self.assertEqual(decoded["Umask"], 0o077)

    def test_cli_rejects_host_option_injection_and_invalid_ports(self):
        for text in ("-oProxyCommand=evil", "user@host", "127.0.0.1;false", "host/path"):
            with self.assertRaises(argparse.ArgumentTypeError):
                setup.host(text)
        for number in (0, 65536):
            with self.assertRaises(argparse.ArgumentTypeError):
                setup.port(number)

    def test_health_disables_proxies_and_requires_status_ok(self):
        class Response:
            status = 200
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, size): return json.dumps({"status": "not-ready"}).encode()
        with patch.object(setup.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = Response()
            with self.assertRaises(setup.SetupError):
                setup.health(8787)
            self.assertEqual(build.call_args.args[0].proxies, {})
            self.assertIsInstance(build.call_args.args[1], setup.NoRedirect)

    def test_openclaw_uses_liveness_and_control_ui_without_hermes_contract(self):
        class Response:
            status = 200
            def __init__(self, body): self.body = body
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, size): return self.body
        with patch.object(setup.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = [Response(b'{"ok":true,"status":"live"}'),
                                                  Response(b'<openclaw-app></openclaw-app>')]
            setup.health(18789, "openclaw", "/openclaw/")
            urls = [call.args[0].full_url for call in build.return_value.open.call_args_list]
            self.assertEqual(urls, ["http://127.0.0.1:18789/healthz", "http://127.0.0.1:18789/openclaw/"])
        with patch.object(setup, "listeners", return_value=["127.0.0.1:18789", "[::1]:18789"]), \
             patch.object(setup, "health"):
            setup.check_listener(18789, "openclaw")
        for path in ("//evil.example", "/?token=secret", "/../", "/%2e%2e/", "/a//b"):
            with self.assertRaises(argparse.ArgumentTypeError):
                setup.ui_path(path)
        self.assertEqual(setup.ui_path("/openclaw"), "/openclaw/")


if __name__ == "__main__":
    unittest.main()
