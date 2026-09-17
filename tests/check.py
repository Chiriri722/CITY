"""Run with python3 tests/check.py; no network or Android required."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CityCLI(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.log = self.home / 'calls.jsonl'
        self.env = dict(os.environ, HOME=str(self.home), PREFIX='/data/data/com.termux/files/usr',
                        PATH=f'{self.bin}:{os.environ["PATH"]}', CITY_CALLS=str(self.log))
        mock = self.bin / 'proot-distro'
        mock.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CITY_CALLS'], 'a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\\n')
if os.environ.get('CITY_MOCK_STDIN'):
    print(sys.stdin.read(), end='')
sys.exit(int(os.environ.get('CITY_MOCK_STATUS', '0')))
''')
        mock.chmod(0o755)

    def run_city(self, *args, **kwargs):
        return subprocess.run(['bash', str(ROOT / 'city.sh'), *args], cwd=self.home,
                              env=self.env, text=True, capture_output=True, **kwargs)

    def test_help_and_catalog_without_termux(self):
        self.env.pop('PREFIX')
        result = self.run_city('--help')
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ('codex', 'opencode', 'install'):
            self.assertIn(name, result.stdout)
        self.assertFalse(self.log.exists())

    def test_invalid_input_has_no_side_effects(self):
        for args in [('install', '../bad'), ('install', 'codex', 'extra'), ('unknown',)]:
            self.assertEqual(self.run_city(*args).returncode, 2)
        self.env['CITY_DISTRO'] = '../../escape'
        self.assertEqual(self.run_city('codex').returncode, 2)
        self.assertFalse(self.log.exists())

    def test_non_termux_rejected(self):
        self.env['PREFIX'] = '/usr'
        self.assertEqual(self.run_city('codex').returncode, 2)
        self.assertFalse(self.log.exists())

    def test_arguments_stdin_and_exit_status_survive(self):
        self.env.update(CITY_MOCK_STDIN='1', CITY_MOCK_STATUS='17')
        result = self.run_city('codex', 'exec', 'two words', '$(touch BAD)', input='prompt\n')
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertEqual(result.stdout, 'prompt\n')
        call = json.loads(self.log.read_text().splitlines()[0])
        self.assertIn('--isolated', call)
        self.assertIn('--shared-home', call)
        self.assertIn('city-ubuntu', call)
        self.assertEqual(call[-3:], ['exec', 'two words', '$(touch BAD)'])
        self.assertFalse((self.home / 'BAD').exists())

    def test_debian_and_opencode_dispatch(self):
        self.env['CITY_DISTRO'] = 'debian'
        result = self.run_city('opencode', '--version')
        self.assertEqual(result.returncode, 0, result.stderr)
        call = json.loads(self.log.read_text())
        self.assertIn('city-debian', call)
        self.assertIn('/opt/city/opencode/bin/opencode', call)

    def test_outside_home_rejected(self):
        self.env['HOME'] = str(self.home / 'nested')
        Path(self.env['HOME']).mkdir()
        self.assertEqual(self.run_city('codex').returncode, 2)
        self.assertFalse(self.log.exists())

    def test_working_directory_with_spaces(self):
        project = self.home / 'my project'
        project.mkdir()
        result = subprocess.run(['bash', str(ROOT / 'city.sh'), 'codex'], cwd=project,
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('/root/my project', json.loads(self.log.read_text()))


    def test_guest_cwd_failure_does_not_run_agent(self):
        self.assertEqual(self.run_city('codex').returncode, 0)
        call = json.loads(self.log.read_text())
        command = call[call.index('--') + 1:]
        command[command.index('/root')] = str(self.home / 'missing')
        marker = self.home / 'ran'
        agent = self.bin / 'fake-agent'
        agent.write_text(f'#!/bin/bash\ntouch "{marker}"\n')
        agent.chmod(0o755)
        command[command.index('/opt/city/codex/bin/codex')] = str(agent)
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())


@unittest.skipUnless(os.environ.get('CITY_INTEGRATION') == '1',
                     'Set CITY_INTEGRATION=1 only in a disposable Linux container (network required).')
class InstallIntegration(unittest.TestCase):
    setUp = CityCLI.setUp
    run_city = CityCLI.run_city

    def test_install_both_repeat_and_integrity_failure(self):
        # Mock only the Android package/container boundary; execute the real guest installer.
        for name, body in {
            'pkg': 'exit 0',
            'dpkg-query': 'echo 5.0.0',
            'dpkg': 'if [[ "$1" == --print-architecture ]]; then echo amd64; else /usr/bin/dpkg "$@"; fi',
        }.items():
            path = self.bin / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)
        (self.bin / 'proot-distro').write_text('''#!/usr/bin/env python3
import os, sys
from pathlib import Path
args = sys.argv[1:]
if args[0] == 'install':
    root = Path(os.environ['PREFIX']) / 'var/lib/proot-distro/containers' / args[2] / 'rootfs'
    root.mkdir(parents=True)
else:
    cmd = args[args.index('--') + 1:]
    os.execv(cmd[0], cmd)
''')
        for _ in range(2):
            result = self.run_city('install', 'all', timeout=600)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        links = {agent: Path('/opt/city', agent).readlink() for agent in ('codex', 'opencode')}
        for agent, version in [('codex', '0.154.0'), ('opencode', '1.18.31')]:
            result = subprocess.run([f'/opt/city/{agent}/bin/{agent}', '--version'],
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(version, result.stdout)
        source = (ROOT / 'city.sh').read_text()
        node_version = re.search(r'node_version=(v[\d.]+)', source)[1]
        node_sha = re.findall(r'node_sha=([a-f0-9]{64})', source)[1]
        result = subprocess.run(['bash', str(ROOT / 'scripts/guest-install.sh'),
                                 'codex', '0.154.0',
                                 'https://registry.npmjs.org/@openai/codex/-/codex-0.154.0.tgz',
                                 '0' * 128, node_version, 'x64', node_sha],
                                text=True, capture_output=True, timeout=120)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(links, {agent: Path('/opt/city', agent).readlink() for agent in links})


if __name__ == '__main__':
    unittest.main()
