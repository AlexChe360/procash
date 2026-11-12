"""Exercise first cutover with fake Docker/HTTP, never a real server."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent
REVISION = 'a' * 40
IMAGE = 'ghcr.io/example/procash-rails@sha256:' + 'b' * 64
FAKE = r'''#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
with open(os.environ['EVENTS'],'a') as f:
    f.write(json.dumps({'tool':os.path.basename(sys.argv[0]),'args':args,'image':os.environ.get('PROCASH_IMAGE'),'port':os.environ.get('PROCASH_BIND_PORT')})+'\n')
if os.path.basename(sys.argv[0])=='curl':
    if os.environ.get('FAIL_CUTOVER') and any('8080/health' in a for a in args):sys.exit(22)
    sys.exit(0)
if args[:2]==['image','inspect']:print('a'*40)
elif args and args[0]=='inspect':
    if '--format' in args:print('sha256:legacy-image')
    else:print(json.dumps([{'Config':{'Env':['SMTP_HOST=smtp.example.test','SMTP_PORT=587','SMTP_SECURITY=starttls','SMTP_FROM=info@example.test','SMTP_PASSWORD=mail-secret']}}]))
elif 'ps' in args:print('legacy-container')
elif any('pg_dump' in a for a in args):print('verified archive')
'''

class RailsDeployTest(unittest.TestCase):
    def run_release(self, password='bootstrap-test-password', fail=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        server = root/'server'
        server.mkdir()
        subprocess.run(['git','init','-q',str(server)],check=True)
        (server/'.env').write_text('existing server environment')
        helpers=root/'helpers';helpers.mkdir()
        for filename in ['rails_deploy.sh','rails_prepare.py']:shutil.copy(SOURCE/filename,helpers/filename)
        (helpers/'compose.production.yml').write_text('name: procash_rails\n')
        binaries=root/'bin';binaries.mkdir()
        for tool in ['docker','curl']:
            path=binaries/tool;path.write_text(FAKE);path.chmod(0o755)
        # macOS lacks flock; it is supplied only in this controlled test fixture.
        (binaries/'flock').write_text('#!/bin/sh\nexit 0\n');(binaries/'flock').chmod(0o755)
        events=root/'events'
        environment=dict(os.environ,PATH=str(binaries)+os.pathsep+os.environ['PATH'],EVENTS=str(events))
        if fail:environment['FAIL_CUTOVER']='1'
        result=subprocess.run(['bash',str(helpers/'rails_deploy.sh'),str(server),IMAGE,REVISION,'example'],input='registry-token\n'+password+'\n',text=True,capture_output=True,env=environment)
        records=[json.loads(line) for line in events.read_text().splitlines()]
        return result, records, server

    def test_missing_password_leaves_public_site_untouched(self):
        result,events,server=self.run_release(password='')
        self.assertNotEqual(0,result.returncode)
        self.assertIn('staged on loopback',result.stdout)
        self.assertFalse(any(e['args']==['compose','stop','app'] for e in events))
        self.assertEqual(0o600,(server/'.deploy/rails/.env').stat().st_mode & 0o777)
        self.assertNotIn('mail-secret',result.stdout+result.stderr)

    def test_success_uses_separate_database_and_starts_worker_after_public_checks(self):
        result,events,server=self.run_release()
        self.assertEqual(0,result.returncode,result.stdout+result.stderr)
        self.assertEqual(IMAGE,(server/'.deploy/rails/active-image').read_text().strip())
        self.assertTrue(list((server/'.deploy/backups').glob('*.dump')))
        stop=next(i for i,e in enumerate(events) if e['args']==['compose','stop','app'])
        bootstrap=next(i for i,e in enumerate(events) if any('bootstrap_admin.rb' in a for a in e['args']))
        self.assertLess(bootstrap,stop)
        worker=next(i for i,e in enumerate(events) if e['args'][-4:]==['up','-d','--no-deps','worker'])
        public=next(i for i,e in enumerate(events) if 'https://procash.kz/documentation' in e['args'])
        self.assertLess(public,worker)
        self.assertNotIn('bootstrap-test-password',result.stdout+result.stderr)

    def test_failed_cutover_restores_original_image_not_rails_image(self):
        result,events,server=self.run_release(fail=True)
        self.assertNotEqual(0,result.returncode)
        restore=[e for e in events if e['args']==['compose','up','-d','--no-deps','--no-build','--pull','never','app']]
        self.assertEqual(1,len(restore))
        self.assertEqual('sha256:legacy-image',restore[0]['image'])
        self.assertFalse((server/'.deploy/rails/active-image').exists())

if __name__=='__main__':unittest.main()
