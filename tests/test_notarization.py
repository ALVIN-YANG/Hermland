import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / "scripts/notarize-macos.sh"
IDENTIFIER = "12345678-1234-1234-1234-123456789abc"


class NotarizationTests(unittest.TestCase):
    def run_fixture(self, mode):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        archive = root / "candidate.zip"
        archive.write_bytes(b"isolated test")
        receipts = root / "receipts"
        receipts.mkdir()
        executable = root / "xcrun"
        executable.write_text("""#!/usr/bin/env bash
set -eu
printf '%s\\n' "$2" >> "$TEST_CALLS"
case "$2" in
 submit) printf '{"id":"12345678-1234-1234-1234-123456789abc"}';;
 wait) [[ "$TEST_MODE" == accepted ]] || exit 69
       printf '{"id":"12345678-1234-1234-1234-123456789abc","status":"Accepted"}';;
 info) if [[ "$TEST_MODE" == recovered ]]; then state=Accepted; else state='In Progress'; fi
       printf '{"id":"12345678-1234-1234-1234-123456789abc","status":"%s"}' "$state";;
 log) exit 0;;
 *) exit 1;;
esac
""")
        executable.chmod(0o700)
        calls = root / "calls"
        env = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
               "TEST_MODE": mode, "TEST_CALLS": str(calls)}
        command = ["bash", str(SCRIPT), str(archive), "test-only", str(receipts)]
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        return result, receipts, calls, command, env

    def test_accepted_and_lost_wait_response_use_same_submission(self):
        for mode in ("accepted", "recovered"):
            result, receipts, calls, command, env = self.run_fixture(mode)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((receipts / "result.json").read_text())["id"], IDENTIFIER)
            self.assertEqual(calls.read_text().splitlines().count("submit"), 1)
            again = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(again.returncode, 0)
            self.assertEqual(calls.read_text().splitlines().count("submit"), 1)

    def test_timeout_keeps_id_and_does_not_claim_accepted_or_upload_again(self):
        result, receipts, calls, _, _ = self.run_fixture("pending")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(IDENTIFIER, result.stderr)
        self.assertNotIn("unbound variable", result.stderr)
        self.assertFalse((receipts / "result.json").exists())
        self.assertEqual(calls.read_text().splitlines().count("submit"), 1)
        self.assertEqual(json.loads((receipts / "submission.json").read_text())["id"], IDENTIFIER)


if __name__ == "__main__":
    unittest.main()
