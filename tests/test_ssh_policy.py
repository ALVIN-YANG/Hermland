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

    def test_disjoint_literal_users_in_include_are_supported_without_rewriting(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            included = root / "other-service.conf"
            content = ("Match User pm-relay\n ForceCommand /bin/false\n"
                       "Match User pm-macbook\n AllowTcpForwarding local\nMatch all\n")
            included.write_text(content)
            config = root / "sshd_config"
            config.write_text(f'Include "{included}"\nPasswordAuthentication no\n'
                              "# Hermland device access (managed)\n"
                              "Match Group hermland-devices\n ForceCommand /bin/false\n")
            policy.check_config(config, protected_users=set())
            self.assertEqual(included.read_text(), content)

    def test_user_patterns_and_reserved_device_names_are_rejected(self):
        for rule in ("User *", "User !hl-*,*", "User hl-device0001", "User hl-relay",
                     "User pm-relay,hl-device0001", "User pm-relay Address 203.0.113.0/24"):
            with self.subTest(rule=rule), tempfile.TemporaryDirectory() as folder:
                config = Path(folder) / "sshd_config"
                config.write_text(f"Match {rule}\n ForceCommand none\n")
                with self.assertRaises(policy.PolicyError):
                    policy.check_config(config, protected_users=set())

    def test_literal_user_in_protected_group_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / "sshd_config"
            config.write_text("Match User pm-relay\n ForceCommand none\n")
            with self.assertRaises(policy.PolicyError):
                policy.check_config(config, protected_users={"pm-relay"})

    def test_match_all_cannot_introduce_a_shadowing_policy(self):
        for content in ("Match User pm-relay\n ForceCommand /bin/false\n"
                        "Match all\n ForceCommand none\n", "Match all\n"):
            with tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                included = root / "other-service.conf"
                included.write_text(content)
                config = root / "sshd_config"
                config.write_text(f'Include "{included}"\n')
                with self.assertRaises(policy.PolicyError):
                    policy.check_config(config, protected_users=set())

    def test_include_inside_foreign_user_block_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / "sshd_config"
            config.write_text("Match User pm-relay\n Include /etc/ssh/other.conf\n")
            with self.assertRaises(policy.PolicyError):
                policy.check_config(config, protected_users=set())


if __name__ == "__main__":
    unittest.main()
