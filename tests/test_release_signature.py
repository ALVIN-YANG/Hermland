import importlib.util
from pathlib import Path
import unittest

module_spec = importlib.util.spec_from_file_location(
    "release_signature", Path(__file__).parents[1] / "scripts" / "verify-macos-signature.py")
signature = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(signature)


class ReleaseSignatureTests(unittest.TestCase):
    def test_formal_signature_needs_all_notarization_prerequisites(self):
        valid = ("Authority=Developer ID Application: Test Publisher (ABCDEFGHIJ)\n"
                 "CodeDirectory v=20500 size=100 flags=0x10000(runtime)\n"
                 "Timestamp=12 Oct 2026\nTeamIdentifier=ABCDEFGHIJ\n")
        self.assertEqual(signature.signature_problems(valid, {}, True), [])
        for line in valid.splitlines(keepends=True):
            self.assertTrue(signature.signature_problems(valid.replace(line, ""), {}, True), line)
        other_certificate = valid.replace("Developer ID Application:", "Apple Distribution:")
        self.assertTrue(signature.signature_problems(other_certificate, {}, True))

    def test_debugger_permission_rejected_even_for_development_release(self):
        ad_hoc = "CodeDirectory v=20400 size=100 flags=0x2(adhoc)\nSignature=adhoc\nTeamIdentifier=not set\n"
        self.assertEqual(signature.signature_problems(ad_hoc, {}), [])
        self.assertTrue(signature.signature_problems(ad_hoc, {"com.apple.security.get-task-allow": True}))
        self.assertTrue(signature.signature_problems(ad_hoc, {}, True))


if __name__ == "__main__":
    unittest.main()
