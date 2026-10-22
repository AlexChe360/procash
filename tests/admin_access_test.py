"""Exercise the real administrator runner with an isolated SSH/Docker endpoint."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

FAKE_SSH = r'''#!/usr/bin/env python3
import json,os,subprocess,sys
from pathlib import Path
p=Path(os.environ['ADMIN_TEST_STATE']); state=json.loads(p.read_text())
state['ssh']=sys.argv[1:]
state['secret_in_environment']='ADMIN_BOOTSTRAP_PASSWORD' in os.environ
p.write_text(json.dumps(state))
if state.get('fail_ssh'): sys.exit(255)
sys.exit(subprocess.run(['/bin/sh','-c',sys.argv[-1]],check=False).returncode)
'''

FAKE_DOCKER = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['ADMIN_TEST_STATE']); state=json.loads(p.read_text())
state['docker']=sys.argv[1:]
state['password']=sys.stdin.read()
p.write_text(json.dumps(state))
if state.get('fail_cli'): sys.exit(1)
print('Administrator saved; previous sessions revoked.')
'''


class AdminAccessTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="procash-admin-test-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        # Quoting must work through an ordinary POSIX SSH login shell.
        self.server = self.path / "server 'quoted' $(touch unexpected-file)"
        self.server.mkdir()
        subprocess.run(["git", "init", "--quiet", str(self.server)], check=True)
        self.state_file = self.path / "state.json"
        self.state_file.write_text("{}")
        self.fake_bin = self.path / "bin"
        self.fake_bin.mkdir()
        for name, script in [("ssh", FAKE_SSH), ("docker", FAKE_DOCKER)]:
            path = self.fake_bin / name
            path.write_text(script)
            path.chmod(0o755)
        self.password = "  fixture-'$`\\-password  "
        self.environment = {
            **os.environ,
            "PATH": str(self.fake_bin) + os.pathsep + os.environ["PATH"],
            "ADMIN_TEST_STATE": str(self.state_file),
            "VPS_HOST": "test.invalid", "VPS_USER": "fixture-user", "VPS_PORT": "2222",
            "DEPLOY_PATH": str(self.server), "ADMIN_EMAIL": "admin@example.test",
            "ADMIN_BOOTSTRAP_PASSWORD": self.password,
        }

    def run_access(self):
        result = subprocess.run(["python3", str(ROOT / "deploy/admin_access.py")], env=self.environment, cwd=self.path, capture_output=True, text=True)
        self.assertNotIn(self.password, result.stdout + result.stderr)
        return result, json.loads(self.state_file.read_text())

    def test_password_uses_stdin_preserving_special_characters_and_not_arguments_or_environment(self):
        result, state = self.run_access()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["password"], self.password + "\n")
        self.assertNotIn(self.password, " ".join(state["ssh"]))
        self.assertFalse(state["secret_in_environment"])
        self.assertIn("StrictHostKeyChecking=yes", state["ssh"])
        self.assertIn("BatchMode=yes", state["ssh"])
        self.assertIn("2222", state["ssh"])
        self.assertEqual(state["docker"], ["compose", "--project-directory", str(self.server), "--env-file", str(self.server / ".env"), "exec", "-T", "app", "procash", "admin", "--email", "admin@example.test"])
        self.assertFalse((self.path / "unexpected-file").exists())
        self.assertFalse((self.server / "unexpected-file").exists())

    def test_invalid_or_missing_credentials_do_not_connect(self):
        for password in ["", "short", "x" * 73, "fixture-password\nextra", "fixture-password\r"]:
            with self.subTest(password_length=len(password)):
                self.environment["ADMIN_BOOTSTRAP_PASSWORD"] = password
                result, state = self.run_access()
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("ssh", state)

    def test_invalid_port_or_email_does_not_connect(self):
        for key, value in [("VPS_PORT", "0"), ("VPS_PORT", "70000"), ("VPS_PORT", "22;id"), ("ADMIN_EMAIL", "invalid"), ("ADMIN_EMAIL", "admin@example.test\n--extra")]:
            with self.subTest(key=key, value=value):
                old = self.environment[key]
                self.environment[key] = value
                result, state = self.run_access()
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("ssh", state)
                self.environment[key] = old

    def test_ssh_failure_does_not_run_administrator_command(self):
        self.state_file.write_text(json.dumps({"fail_ssh": True}))
        result, state = self.run_access()
        self.assertEqual(result.returncode, 255)
        self.assertNotIn("docker", state)

    def test_failed_administrator_command_fails_workflow(self):
        self.state_file.write_text(json.dumps({"fail_cli": True}))
        result, _ = self.run_access()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Administrator saved", result.stdout)


if __name__ == "__main__":
    unittest.main()
