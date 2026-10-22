"""Exercise deployment ordering/rollback with real Git and Go, and a fake Docker CLI."""
import base64
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
IMAGE = "ghcr.io/alexche360/procash@sha256:" + "b" * 64
OLD_IMAGE = "sha256:" + "a" * 64
NEW_IMAGE = "sha256:" + "c" * 64

FAKE_DOCKER = r'''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
p=Path(os.environ['DEPLOY_TEST_STATE']); state=json.loads(p.read_text()); args=sys.argv[1:]
state['events'].append(['docker',args]); p.write_text(json.dumps(state))
def finish(code=0, output=''):
    if output: print(output)
    sys.exit(code)
if args[:1]==['--config']:
    if args[2]=='login':
        assert sys.stdin.read().strip()=='fixture-registry-token'
    finish()
if args[:2]==['image','inspect']:
    if '.Config.Labels' in args[3]: finish(output=('0'*40 if state['fail']=='image' else state['revision']))
    finish(output='sha256:'+'c'*64)
if args[:1]==['inspect']:
    finish(output=('true' if '.State.Running' in args[2] else 'sha256:'+('c' if state['active']=='new' else 'a')*64))
if args[:1]==['run']:
    i=args.index('/deploy/.env')
    command=[os.environ['DEPLOY_TEST_BINARY'],'prepare-env',str(Path.cwd()/'.env')]+args[i+1:]
    finish(subprocess.run(command,input=sys.stdin.read(),text=True).returncode)
assert args[:1]==['compose'],args
args=args[5:]
if args[0]=='ps': finish(output='app-container')
if args[0]=='up':
    if args[-1]=='app':
        candidate=os.environ.get('PROCASH_IMAGE','').startswith('ghcr.io/')
        state['active']='new' if candidate else 'old'; p.write_text(json.dumps(state))
        if candidate and state['fail']=='health': finish(1)
    finish()
if args[0]=='exec' and args[2]=='db':
    if args[3]=='sh':
        finish(31 if state['fail']=='backup' else 0, '' if state['fail']=='backup' else 'PGDMP-fixture')
    assert sys.stdin.read().startswith('PGDMP-fixture')
    finish(output='verified archive')
if args[0]=='exec':
    if args[3]=='sh': finish(1)  # Previous application was Spring, without PHP.
    finish()
if args[0]=='run':
    if args[-1]=='check-config': finish(19 if state['fail']=='config' else 0)
    assert (Path.cwd()/'revision.txt').read_text()=='new'
    assert any(e[0]=='docker' and 'pg_restore' in e[1] for e in state['events'])
    finish(17 if state['fail']=='migration' else 0)
if args[0] in ['config','logs','stop']: finish()
raise AssertionError(args)
'''

FAKE_CURL = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['DEPLOY_TEST_STATE']);state=json.loads(p.read_text())
state['events'].append(['curl',sys.argv[1:]]);p.write_text(json.dumps(state))
sys.exit(22 if state['fail']=='login' and sys.argv[-1].endswith('/login') else 0)
'''


class DeploymentTest(unittest.TestCase):
    def setUp(self):
        parent = ROOT / ".deploy/testing"
        parent.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="deploy-test-", dir=parent)
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name)
        self.origin = self.path / "origin"
        self.server = self.path / "server"
        self.origin.mkdir()
        self.git("init", "--initial-branch=main", cwd=self.origin)
        (self.origin / "revision.txt").write_text("old")
        (self.origin / ".gitignore").write_text(".env\n")
        self.commit()
        self.old_revision = self.git("rev-parse", "HEAD", cwd=self.origin)
        (self.origin / "revision.txt").write_text("new")
        (self.origin / ".gitignore").write_text(".env\n.deploy/\n")
        self.commit()
        self.revision = self.git("rev-parse", "HEAD", cwd=self.origin)
        self.git("clone", str(self.origin), str(self.server), cwd=self.path)
        self.git("checkout", "--detach", self.old_revision)
        self.env_file = self.server / ".env"
        self.env_file.write_text("# Preserve server settings\nPOSTGRES_PASSWORD='fixture-password'\nPROCASH_IMAGE=ghcr.io/alexche360/procash:legacy\nAPP_KEY=\nCUSTOM='$(touch must-not-execute)'\n")
        self.state_file = self.path / "state.json"
        self.state_file.write_text(json.dumps({"events": [], "active": "old", "fail": "", "revision": self.revision}))
        fake_bin = self.path / "bin"
        fake_bin.mkdir()
        for name, content in [("docker", FAKE_DOCKER), ("curl", FAKE_CURL)]:
            p = fake_bin / name
            p.write_text(content)
            p.chmod(0o755)
        binary = os.environ.get("PROCASH_TEST_BINARY", "/workspace/procash-go-runtime/procash")
        if not Path(binary).is_file():
            self.fail("Build the Go binary and set PROCASH_TEST_BINARY before deployment tests")
        self.environment = {
            **os.environ,
            "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
            "DEPLOY_TEST_STATE": str(self.state_file),
            "DEPLOY_TEST_BINARY": binary,
        }
        # Do not inherit a developer's image override into a simulated server.
        self.environment.pop("PROCASH_IMAGE", None)

    def git(self, *args, cwd=None):
        return subprocess.check_output(["git", *args], cwd=cwd or self.server, text=True, stderr=subprocess.DEVNULL).strip()

    def commit(self):
        self.git("add", ".", cwd=self.origin)
        self.git("-c", "user.name=Deploy tests", "-c", "user.email=deploy-tests@example.test", "commit", "-m", "fixture", cwd=self.origin)

    def state(self):
        return json.loads(self.state_file.read_text())

    def run_deploy(self, failure=""):
        state = self.state()
        state["fail"] = failure
        self.state_file.write_text(json.dumps(state))
        result = subprocess.run(["bash", str(ROOT / "deploy/deploy.sh"), str(self.server), IMAGE, self.revision, "fixture-user"], input="fixture-registry-token\n{}\n", text=True, capture_output=True, env=self.environment)
        self.assertNotIn("fixture-registry-token", result.stdout + result.stderr)
        for kind, argv in self.state()["events"]:
            if kind == "docker" and "login" in argv:
                self.assertFalse(Path(argv[1]).exists(), "Temporary registry credentials were not removed")
        return result

    def assert_restored(self):
        self.assertEqual(self.git("rev-parse", "HEAD"), self.old_revision)
        self.assertEqual(self.state()["active"], "old")
        self.assertIn("PROCASH_IMAGE=ghcr.io/alexche360/procash:legacy", self.env_file.read_text())

    def test_success_uses_tested_commit_creates_backup_and_preserves_key_on_repeat(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.revision)
        self.assertEqual(self.state()["active"], "new")
        env = self.env_file.read_text()
        key = next(line.removeprefix("APP_KEY=") for line in env.splitlines() if line.startswith("APP_KEY="))
        self.assertEqual(len(base64.b64decode(key.removeprefix("base64:"))), 32)
        self.assertNotIn(key, result.stdout + result.stderr)
        self.assertIn("PROCASH_IMAGE=" + IMAGE, env)
        self.assertIn("CUSTOM='$(touch must-not-execute)'", env)
        self.assertFalse((self.server / "must-not-execute").exists())
        self.assertEqual(stat.S_IMODE(self.env_file.stat().st_mode), 0o600)
        backups = list((self.server / ".deploy/backups").glob("*.dump"))
        self.assertEqual(len(backups), 1)
        self.assertTrue(backups[0].read_bytes().startswith(b"PGDMP"))
        repeated = self.run_deploy()
        self.assertEqual(repeated.returncode, 0, repeated.stdout + repeated.stderr)
        self.assertEqual(self.env_file.read_text(), env)

    def test_migration_failure_keeps_previous_application_running(self):
        result = self.run_deploy("migration")
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()
        self.assertFalse(any(e[0] == "docker" and "--force-recreate" in e[1] for e in self.state()["events"]))

    def test_failed_container_health_restores_previous_image(self):
        result = self.run_deploy("health")
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()
        self.assertIn("Previous application image restored", result.stderr)

    def test_failed_http_check_restores_previous_image(self):
        result = self.run_deploy("login")
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()

    def test_missing_mail_configuration_keeps_previous_release(self):
        result = self.run_deploy("config")
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()
        self.assertIn("Production mail configuration", result.stdout)
        self.assertFalse(any("pg_dump" in str(e) or "migrate" in e[1] for e in self.state()["events"]))

    def test_failed_backup_never_runs_migrations(self):
        result = self.run_deploy("backup")
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()
        self.assertFalse(any("migrate" in e[1] for e in self.state()["events"]))
        self.assertEqual(list((self.server / ".deploy/backups").glob("*.dump")), [])

    def test_wrong_image_revision_does_not_change_server(self):
        before = self.env_file.read_text()
        result = self.run_deploy("image")
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()
        self.assertEqual(self.env_file.read_text(), before)
        self.assertFalse((self.server / ".deploy").exists())

    def test_local_changes_are_preserved(self):
        (self.server / "revision.txt").write_text("local changes")
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.server / "revision.txt").read_text(), "local changes")
        self.assertEqual(self.state()["events"], [])

    def test_invalid_existing_key_is_never_replaced(self):
        before = self.env_file.read_text().replace("APP_KEY=", "APP_KEY=invalid-existing-key")
        self.env_file.write_text(before)
        result = self.run_deploy()
        self.assertNotEqual(result.returncode, 0)
        self.assert_restored()
        self.assertEqual(self.env_file.read_text(), before)


if __name__ == "__main__":
    unittest.main()
