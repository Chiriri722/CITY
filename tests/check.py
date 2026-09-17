"""Run with python3 tests/check.py; no network or Android required."""
import json
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest import mock

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

    def test_install_passes_local_archive_to_proot_580(self):
        # Stop at the real failing boundary; no rootfs or package changes.
        self.env['PREFIX'] = '/data/data/com.termux.citycheck/files/usr'
        for name, body in {
            'pkg': 'exit 0',
            'dpkg-query': 'echo 5.8.0',
            'dpkg': 'if [[ "$1" == --print-architecture ]]; then echo aarch64; else /usr/bin/dpkg "$@"; fi',
            'python3': 'exit 0',
            'proot-distro': 'printf "%s\\n" "$@" >"$CITY_CALLS"; exit 77',
        }.items():
            path = self.bin / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)
        for distro in ('ubuntu', 'debian'):
            with self.subTest(distro=distro):
                self.env['CITY_DISTRO'] = distro
                result = self.run_city('install', 'all')
                self.assertEqual(result.returncode, 77, result.stderr)
                call = self.log.read_text().splitlines()
                self.assertEqual(call[:3], ['install', '--name', f'city-{distro}'])
                self.assertTrue(call[3].startswith('/'), call[3])
                self.assertTrue(call[3].endswith('/rootfs.tar.gz'), call[3])
                self.assertFalse(list((self.home / '.local/share/city').glob('rootfs.*')))
        self.log.unlink()
        (self.bin / 'python3').write_text('#!/bin/bash\nexit 78\n')
        self.assertEqual(self.run_city('install', 'all').returncode, 78)
        self.assertFalse(self.log.exists(), 'PRoot must not run after a failed download')
        self.assertFalse(list((self.home / '.local/share/city').glob('rootfs.*')))

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
            # Use the distro interpreter, not a Python preinstalled in the test image.
            result = subprocess.run(['/usr/bin/python3', '-c',
                                     'from cryptography.fernet import Fernet; '
                                     'f = Fernet(Fernet.generate_key()); '
                                     'assert f.decrypt(f.encrypt(b"city")) == b"city"'],
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(Path('/usr/bin/python').samefile('/usr/bin/python3'))
        with tempfile.TemporaryDirectory() as directory:
            venv = Path(directory) / 'venv'
            for command in [
                ['/usr/bin/python3', '-m', 'venv', str(venv)],
                [str(venv / 'bin/python'), '-m', 'pip', 'install', '--only-binary=:all:', 'cryptography'],
                [str(venv / 'bin/python'), '-c', 'from cryptography.fernet import Fernet; '
                 'f = Fernet(Fernet.generate_key()); assert f.decrypt(f.encrypt(b"venv")) == b"venv"'],
            ]:
                result = subprocess.run(command, text=True, capture_output=True, timeout=180)
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


class RootfsIntegrity(unittest.TestCase):
    def test_verified_chain_and_corruption_rejection(self):
        spec = importlib.util.spec_from_file_location('rootfs', ROOT / 'scripts/fetch-rootfs.py')
        rootfs = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(rootfs)
        blob = b'fake gzip rootfs bytes'
        sha = lambda data: 'sha256:' + hashlib.sha256(data).hexdigest()
        manifest = json.dumps({'layers': [{'digest': sha(blob), 'size': len(blob),
                              'mediaType': 'application/vnd.oci.image.layer.v1.tar+gzip'}]}).encode()
        index = json.dumps({'manifests': [{'digest': sha(manifest),
                           'platform': {'os': 'linux', 'architecture': 'arm64'}}]}).encode()
        image = 'ubuntu@' + sha(index)
        responses = [b'{"token":"anonymous-test-token"}', index, manifest, blob]
        for corrupt_at in (None, 1, 2, 3):
            with self.subTest(corrupt_at=corrupt_at), tempfile.TemporaryDirectory() as directory:
                opener = mock.Mock()
                data = [value + b'corruption' if i == corrupt_at else value
                        for i, value in enumerate(responses)]
                opener.open.side_effect = [io.BytesIO(value) for value in data]
                destination = Path(directory) / 'rootfs.tar.gz'
                with mock.patch.object(rootfs.urllib.request, 'build_opener', return_value=opener):
                    if corrupt_at is None:
                        rootfs.download(image, 'arm64', destination)
                        self.assertEqual(destination.read_bytes(), blob)
                    else:
                        with self.assertRaisesRegex(ValueError, 'checksum'):
                            rootfs.download(image, 'arm64', destination)


@unittest.skipUnless(os.environ.get('CITY_PROOT_SOURCE'),
                     'Set CITY_PROOT_SOURCE to a v5.8.0 checkout in a disposable Linux container.')
class RealProotIntegration(unittest.TestCase):
    def test_pinned_images_with_proot_580(self):
        source = (ROOT / 'city.sh').read_text()
        env = dict(os.environ, PYTHONPATH=os.environ.get('CITY_PROOT_SOURCE', ''))
        pd = ['python3', '-c', 'from proot_distro.cli import main; main()']
        with tempfile.TemporaryDirectory() as directory:
            env.update(HOME=directory, XDG_DATA_HOME=directory + '/data',
                       XDG_CACHE_HOME=directory + '/cache')
            for distro, release in [('ubuntu', '24.04'), ('debian', '12')]:
                image = re.search(rf'{distro}\) image=([^\s;]+)', source)[1]
                for arch in ('arm64', 'x64'):
                    with self.subTest(distro=distro, arch=arch):
                        archive = f'{directory}/{distro}-{arch}.tar.gz'
                        name = f'city-{distro}-{arch}'
                        commands = [
                            ['python3', str(ROOT / 'scripts/fetch-rootfs.py'), image, arch, archive],
                            [*pd, 'install', '--name', name,
                             '--architecture', 'aarch64' if arch == 'arm64' else 'x86_64', archive],
                        ]
                        for command in commands:
                            result = subprocess.run(command, env=env, text=True,
                                                    capture_output=True, timeout=300)
                            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        os_release = Path(directory, 'data/proot-distro/containers', name,
                                          'rootfs/etc/os-release').read_text()
                        self.assertIn(f'VERSION_ID="{release}"', os_release)
                        if arch == 'x64':
                            result = subprocess.run([*pd, 'login', name,
                                                     '--', '/bin/bash', '-c', 'printf city-guest-ok'],
                                                    env=env, text=True, capture_output=True, timeout=30)
                            self.assertEqual(result.returncode, 0, result.stderr)
                            self.assertIn('city-guest-ok', result.stdout)
                        print(f'\nVerified real PRoot-Distro: {distro} {release} {arch}', flush=True)


if __name__ == '__main__':
    unittest.main()
