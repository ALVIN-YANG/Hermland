"""Reject conditional SSH policy conflicts before any account/key/config write."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("ssh_policy", Path(__file__).parents[1] / "deploy/ssh_policy.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class SSHPolicyTests(unittest.TestCase):
    def test_address_specific_override_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / "sshd_config"
            config.write_text("Match Address 203.0.113.0/24\n ForceCommand none\n")
            with self.assertRaises(policy.PolicyError):
                policy.check_config(config)

    def test_nested_include_cannot_hide_a_match(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            included = root / "with spaces.conf"
            included.write_text("mAtCh=Address 203.0.113.0/24\n ForceCommand internal-sftp\n")
            config = root / "sshd_config"
            config.write_text(f'Include "{included}"\n')
            with self.assertRaises(policy.PolicyError):
                policy.check_config(config)

    def test_global_config_and_our_managed_groups_are_supported(self):
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / "sshd_config"
            config.write_text("Port 22\nPasswordAuthentication no\n"
                              "# Hermland device access (managed)\n"
                              "Match Group hermland-devices\n ForceCommand /bin/false\n"
                              "# Hermland relay access (managed)\n"
                              "Match Group hermland-relay\n ForceCommand /bin/false\n")
            policy.check_config(config)

    def test_unmarked_or_spoofed_managed_group_is_rejected(self):
        for content in ("Match Group hermland-devices\n", "# Hermland device access (managed)\n"
                        "Match Address 203.0.113.0/24\n", "# Hermland device access (managed)\n"
                        "Match Group hermland-devices,staff\n"):
            with tempfile.TemporaryDirectory() as folder:
                config = Path(folder) / "sshd_config"
                config.write_text(content)
                with self.assertRaises(policy.PolicyError):
                    policy.check_config(config)

    def test_include_cycle_is_rejected_without_recursing_forever(self):
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / "sshd_config"
            config.write_text(f"Include {config}\n")
            with self.assertRaises(policy.PolicyError):
                policy.check_config(config)


if __name__ == "__main__":
    unittest.main()
