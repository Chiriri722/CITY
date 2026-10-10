"""Run with python3 tests/check.py; no network or Android required."""
import json
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
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
                        PATH=f'{self.bin}:{os.environ["PATH"]}', CITY_CALLS=str(self.log),
                        CITY_DISTRO='ubuntu')
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
        for name in ('codex', 'opencode', 'antigravity', 'grok', 'muse', 'install'):
            self.assertIn(name, result.stdout)
        self.assertFalse(self.log.exists())

    def test_invalid_input_has_no_side_effects(self):
        for args in [('install', '../bad'), ('install', 'codex', 'extra'), ('unknown',),
                     ('status', 'extra'), ('update', '../bad'), ('update', 'all', 'extra')]:
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

    def test_phase_two_dispatch(self):
        for agent, binary in [('antigravity', 'agy'), ('grok', 'grok'), ('muse', 'muse')]:
            with self.subTest(agent=agent):
                result = self.run_city(agent, '--version')
                self.assertEqual(result.returncode, 0, result.stderr)
                call = json.loads(self.log.read_text().splitlines()[-1])
                self.assertIn(f'/opt/city/{agent}/bin/{binary}', call)
                self.assertEqual(call[-1], '--version')
                self.assertIn('--isolated', call)

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


class EnvironmentReuse(unittest.TestCase):
    def setUp(self):
        CityCLI.setUp(self)
        self.checkout = self.home / 'CITY3'
        self.checkout.mkdir()
        shutil.copytree(ROOT / 'scripts', self.checkout / 'scripts')
        self.containers = self.home / 'containers'
        self.script = self.checkout / 'city.sh'
        self.script.write_text((ROOT / 'city.sh').read_text().replace(
            '$PREFIX/var/lib/proot-distro/containers', str(self.containers)))
        self.rootfs = self.containers / 'city-ubuntu/rootfs'
        self.origin = 'ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517'
        for name, body in {
            'dpkg': 'if [[ "$1" == --print-architecture ]]; then echo amd64; else /usr/bin/dpkg "$@"; fi',
            'dpkg-query': 'echo 5.8.0',
            'pkg': 'echo unexpected-package-write >> "$HOME/effects"; exit 0',
        }.items():
            path = self.bin / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)

    def run_city(self, *args, **kwargs):
        return subprocess.run(['bash', str(self.script), *args], cwd=self.home,
                              env=self.env, text=True, capture_output=True, **kwargs)

    def make_environment(self):
        (self.rootfs / 'etc').mkdir(parents=True)
        (self.rootfs / 'etc/os-release').write_text('ID=ubuntu\nVERSION_ID="24.04"\n')
        (self.rootfs / 'usr/bin').mkdir(parents=True)
        header = b'\x7fELF\x02\x01' + b'\x00' * 12 + b'\x3e\x00'
        (self.rootfs / 'usr/bin/bash').write_bytes(header)
        (self.rootfs / '.city-owner').write_text(self.origin + '\n')

    def make_agent(self, name='opencode', version='1.18.31'):
        target = self.rootfs / f'opt/city/{name}-{version}'
        (target / 'bin').mkdir(parents=True)
        binary = target / 'bin' / ('agy' if name == 'antigravity' else name)
        binary.write_text('#!/bin/sh\necho should-not-execute >> "$HOME/effects"\n')
        binary.chmod(0o755)
        (target / '.city-sha512').write_text('1' * 128 + '\n')
        (target.parent / name).symlink_to(f'/opt/city/{name}-{version}')

    def test_status_missing_and_legacy_is_read_only(self):
        result = self.run_city('status')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('missing', result.stdout)
        self.assertFalse(self.containers.exists())
        self.make_environment()
        self.make_agent()
        result = self.run_city('status')
        self.assertEqual(result.returncode, 0, result.stderr)
        for value in ('CITY3', 'city-ubuntu', 'legacy', 'opencode', '1.18.31'):
            self.assertIn(value, result.stdout)
        self.assertEqual((self.rootfs / '.city-owner').read_text(), self.origin + '\n')
        self.assertFalse(self.log.exists())
        self.assertFalse((self.home / 'effects').exists())
        self.assertFalse((self.home / '.local').exists())

    def test_update_requires_existing_environment_and_agent(self):
        result = self.run_city('update')
        self.assertEqual(result.returncode, 2)
        self.assertIn('install', result.stderr)
        self.assertFalse(self.containers.exists())
        self.make_environment()
        result = self.run_city('update', 'muse')
        self.assertEqual(result.returncode, 2)
        self.assertIn('install muse', result.stderr)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.home / 'effects').exists())

    def test_update_migrates_once_and_preserves_data(self):
        self.make_environment()
        self.make_agent()
        (self.home / 'project.txt').write_text('keep project')
        (self.rootfs / 'private.txt').write_text('keep guest')
        (self.containers / 'ubuntu').mkdir()
        (self.containers / 'ubuntu/keep').write_text('other distro')
        before = (self.rootfs / 'private.txt').stat().st_ino
        for args in [('update',), ('update', 'all'), ('update', 'opencode')]:
            result = self.run_city(*args)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        owner = (self.rootfs / '.city-owner').read_text()
        self.assertEqual(owner.splitlines(), ['CITY_ENV_V1', 'ubuntu', '24.04', 'x64', self.origin])
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(len(calls), 3)
        self.assertTrue(all(call[0] == 'login' and call[-7] == 'opencode' for call in calls))
        self.assertEqual((self.rootfs / 'private.txt').stat().st_ino, before)
        self.assertEqual((self.home / 'project.txt').read_text(), 'keep project')
        self.assertEqual((self.containers / 'ubuntu/keep').read_text(), 'other distro')
        self.assertFalse((self.home / 'effects').exists())
        self.assertEqual(sorted(p.name for p in self.containers.iterdir()), ['city-ubuntu', 'ubuntu'])

    def test_future_image_pin_keeps_known_environment(self):
        self.make_environment()
        self.make_agent()
        self.script.write_text(self.script.read_text().replace('image=' + self.origin,
                                                              'image=ubuntu@sha256:' + '2' * 64, 1))
        result = self.run_city('update')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.rootfs / '.city-owner').read_text().splitlines()[-1], self.origin)

    def test_debian_legacy_and_arm64_metadata(self):
        self.rootfs = self.containers / 'city-debian/rootfs'
        self.origin = 'debian@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241'
        self.env['CITY_DISTRO'] = 'debian'
        self.make_environment()
        self.make_agent()
        (self.rootfs / 'etc/os-release').write_text('ID=debian\nVERSION_ID="12"\n')
        (self.rootfs / 'usr/bin/bash').write_bytes(b'\x7fELF\x02\x01' + b'\0' * 12 + b'\xb7\0')
        (self.bin / 'dpkg').write_text('#!/bin/bash\nif [[ "$1" == --print-architecture ]]; then echo aarch64; else /usr/bin/dpkg "$@"; fi\n')
        self.script.write_text(self.script.read_text().replace('image=' + self.origin,
                                                              'image=debian@sha256:' + '2' * 64, 1))
        result = self.run_city('update')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        owner = (self.rootfs / '.city-owner').read_text()
        self.assertEqual(owner.splitlines(), ['CITY_ENV_V1', 'debian', '12', 'arm64', self.origin])
        result = self.run_city('status')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Environment: managed', result.stdout)
        self.assertEqual((self.rootfs / '.city-owner').read_text(), owner)

    def test_checkouts_share_one_environment(self):
        self.make_environment()
        for name in ('CITY', 'CITY2', 'CITY3'):
            checkout = self.home / name
            if checkout != self.checkout:
                shutil.copytree(self.checkout, checkout)
            self.script = checkout / 'city.sh'
            result = self.run_city('status')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f'Rootfs: {self.rootfs}', result.stdout)
        self.assertEqual(len(list(self.containers.iterdir())), 1)
        result = self.run_city('update')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('no installed agents', result.stdout)
        self.assertFalse(self.log.exists())

    def test_invalid_agent_link_and_owner_symlink_fail_closed(self):
        self.make_environment()
        self.make_agent()
        link = self.rootfs / 'opt/city/opencode'
        link.unlink()
        link.symlink_to('/tmp/unmanaged')
        for command in ('status', 'update'):
            self.assertEqual(self.run_city(command).returncode, 2)
        self.assertFalse(self.log.exists())
        owner = self.rootfs / '.city-owner'
        owner.unlink()
        other = self.home / 'unrelated-file'
        other.write_text(self.origin + '\n')
        owner.symlink_to(other)
        self.assertEqual(self.run_city('update').returncode, 2)
        self.assertEqual(other.read_text(), self.origin + '\n')
        self.assertFalse(self.log.exists())

    def test_unknown_or_incompatible_environment_is_not_modified(self):
        self.make_environment()
        self.make_agent()
        owner = self.rootfs / '.city-owner'
        for value in ('ubuntu@sha256:' + 'f' * 64, 'CITY_ENV_V9', ''):
            owner.write_text(value + '\n')
            self.assertEqual(self.run_city('update').returncode, 2)
            self.assertEqual(owner.read_text(), value + '\n')
        owner.write_text(self.origin + '\n')
        (self.rootfs / 'etc/os-release').write_text('ID=debian\nVERSION_ID="12"\n')
        self.assertEqual(self.run_city('update').returncode, 2)
        (self.rootfs / 'etc/os-release').write_text('ID=ubuntu\nVERSION_ID="24.04"\n')
        (self.rootfs / 'usr/bin/bash').write_bytes(b'\x7fELF\x02\x01' + b'\0' * 12 + b'\xb7\0')
        self.assertEqual(self.run_city('update').returncode, 2)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.home / 'effects').exists())


@unittest.skipUnless(os.environ.get('CITY_INTEGRATION') == '1',
                     'Set CITY_INTEGRATION=1 only in a disposable Linux container (network required).')
class InstallIntegration(unittest.TestCase):
    setUp = CityCLI.setUp
    run_city = CityCLI.run_city

    def run_guest(self, *command, **kwargs):
        return subprocess.run(['proot-distro', 'login', '--shared-home',
                               'city-' + self.env.get('CITY_DISTRO', 'ubuntu'), '--', *command],
                              env=self.env, text=True, capture_output=True, **kwargs)

    def test_install_all_repeat_and_integrity_failure(self):
        # Emulate the Android CLI boundary, but install and execute inside a real PRoot.
        self.env['PREFIX'] = '/data/data/com.termux.citycheck' + self.home.name + '/files/usr'
        self.env['CITY_DISTRO'] = os.environ.get('CITY_DISTRO', 'ubuntu')
        for name, body in {
            'pkg': 'exit 0',
            'dpkg-query': 'echo 5.0.0',
            'dpkg': 'if [[ "$1" == --print-architecture ]]; then echo amd64; else /usr/bin/dpkg "$@"; fi',
        }.items():
            path = self.bin / name
            path.write_text('#!/bin/bash\n' + body + '\n')
            path.chmod(0o755)
        (self.bin / 'proot-distro').write_text('''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['CITY_CALLS'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
if args[0] == 'install':
    root = Path(os.environ['PREFIX']) / 'var/lib/proot-distro/containers' / args[2] / 'rootfs'
    root.mkdir(parents=True)
    subprocess.run(['tar', '-xzf', args[3], '-C', str(root)], check=True)
else:
    name = args[args.index('--') - 1]
    root = Path(os.environ['PREFIX']) / 'var/lib/proot-distro/containers' / name / 'rootfs'
    cmd = args[args.index('--') + 1:]
    proot = ['proot', '-0', '-r', str(root), '-b', '/dev', '-b', '/proc', '-b', '/sys',
             '-b', '/etc/resolv.conf', '-w', '/root']
    if '--shared-home' in args:
        proot += ['-b', os.environ['HOME'] + ':/root']
    os.execvp('proot', proot + cmd)
''')
        rootfs = Path(self.env['PREFIX'], 'var/lib/proot-distro/containers',
                      'city-' + self.env.get('CITY_DISTRO', 'ubuntu'), 'rootfs')
        (self.home / 'project.txt').write_text('preserve this project')
        for operation in [('install', 'all'), ('update',), ('update', 'all')]:
            result = self.run_city(*operation, timeout=1800)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # Use the distro interpreter, not a Python preinstalled in the test image.
            result = self.run_guest('/usr/bin/python3', '-c',
                                     'from cryptography.fernet import Fernet; '
                                     'f = Fernet(Fernet.generate_key()); '
                                     'assert f.decrypt(f.encrypt(b"city")) == b"city"')
            self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_guest('/usr/bin/python', '-c',
                                'import os; assert os.path.samefile("/usr/bin/python", "/usr/bin/python3")')
        self.assertEqual(result.returncode, 0, result.stderr)
        for command in [
            ['/usr/bin/python3', '-m', 'venv', '/root/test-venv'],
            ['/root/test-venv/bin/python', '-m', 'pip', 'install', '--only-binary=:all:', 'cryptography'],
            ['/root/test-venv/bin/python', '-c', 'from cryptography.fernet import Fernet; '
             'f = Fernet(Fernet.generate_key()); assert f.decrypt(f.encrypt(b"venv")) == b"venv"'],
        ]:
            result = self.run_guest(*command, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        releases = [('codex', 'codex', '0.154.0'), ('opencode', 'opencode', '1.18.31'),
                    ('antigravity', 'agy', '1.3.1'), ('grok', 'grok', '1.0.46'),
                    ('muse', 'muse', '1.4.3-R5018.1')]
        links = {agent: (rootfs / 'opt/city' / agent).readlink() for agent, _, _ in releases}
        for agent, binary, version in releases:
            with self.subTest(agent=agent):
                self.assertTrue((rootfs / str(links[agent]).lstrip('/') / 'bin' / binary).is_file())
                result = self.run_city(agent, '--version', timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(version, result.stdout)
        source = (ROOT / 'city.sh').read_text()
        node_version = re.search(r'node_version=(v[\d.]+)', source)[1]
        node_sha = re.findall(r'node_sha=([a-f0-9]{64})', source)[1]
        result = self.run_guest('bash', '-s', '--', 'codex', '0.154.0',
                                 'https://registry.npmjs.org/@openai/codex/-/codex-0.154.0.tgz',
                                 '0' * 128, node_version, 'x64', node_sha,
                                 input=(ROOT / 'scripts/guest-install.sh').read_text(), timeout=120)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(links, {agent: (rootfs / 'opt/city' / agent).readlink() for agent in links})
        result = self.run_city('status')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Environment: managed', result.stdout)
        self.assertEqual((self.home / 'project.txt').read_text(), 'preserve this project')
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertEqual(sum(call[0] == 'install' for call in calls), 1)


class NativeInstaller(unittest.TestCase):
    def test_native_integrity_startup_and_atomic_upgrade(self):
        # Redirect only the install root and network/package boundaries. Run the real
        # checksum, extraction, startup, marker and atomic-link logic in a temp directory.
        for agent, binary in [('antigravity', 'agy'), ('muse', 'muse')]:
            for arch in ('arm64', 'x64'):
                with self.subTest(agent=agent, arch=arch), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    city = root / 'city'
                    node = city / 'node-v1.0.0'
                    node.mkdir(parents=True)
                    (node / '.city-sha256').write_text('1' * 64 + '\n')
                    mocks = node / 'bin'
                    mocks.mkdir()
                    payload = root / 'download'
                    for name, body in [('apt-get', 'exit 0'),
                                       ('curl', 'cp -- "$CITY_TEST_PAYLOAD" "${@: -1}"')]:
                        path = mocks / name
                        path.write_text('#!/bin/bash\n' + body + '\n')
                        path.chmod(0o755)
                    installer = root / 'install.sh'
                    installer.write_text((ROOT / 'scripts/guest-install.sh').read_text().replace(
                        '/opt/city', str(city)))
                    env = dict(os.environ, PATH=f'{mocks}:{os.environ["PATH"]}',
                               CITY_TEST_PAYLOAD=str(payload))
                    algorithm = 'sha256' if agent == 'muse' else 'sha512'

                    def build_payload(status=0):
                        content = f'#!/bin/sh\necho native-test\nexit {status}\n'.encode()
                        if agent == 'antigravity':
                            with tarfile.open(payload, 'w:gz') as archive:
                                entry = tarfile.TarInfo('antigravity')
                                entry.size = len(content)
                                entry.mode = 0o755
                                archive.addfile(entry, io.BytesIO(content))
                        else:
                            payload.write_bytes(content)
                        return hashlib.new(algorithm, payload.read_bytes()).hexdigest()

                    def arguments(major, digest):
                        version = f'{major}.0.0' + ('-R1.1' if agent == 'muse' else '')
                        if agent == 'muse':
                            platform = 'aarch64' if arch == 'arm64' else 'x86'
                            url = ('https://lookaside.facebook.com/lookaside/muse/download/'
                                   f'?channel=muse&version={version}&file=muse-{platform}-linux')
                        else:
                            platform = 'linux-arm' if arch == 'arm64' else 'linux-x64'
                            url = ('https://storage.googleapis.com/antigravity-public/antigravity-cli/'
                                   f'{version}-4582356770750464/{platform}/cli_linux_{arch}.tar.gz')
                        return [agent, version, url, digest, 'v1.0.0', arch, '1' * 64]

                    def run(args):
                        return subprocess.run(['bash', str(installer), *args], env=env,
                                              text=True, capture_output=True, timeout=20)

                    digest = build_payload()
                    first = arguments(1, digest)
                    for _ in range(2):
                        result = run(first)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    link = city / agent
                    original = link.readlink()
                    self.assertTrue((link / 'bin' / binary).is_file())
                    bad = arguments(2, '0' * len(digest))
                    self.assertNotEqual(run(bad).returncode, 0)
                    self.assertEqual(link.readlink(), original)
                    bad = arguments(2, build_payload(status=71))
                    self.assertEqual(run(bad).returncode, 71)
                    self.assertEqual(link.readlink(), original)
                    self.assertFalse((city / f'{agent}-{bad[1]}').exists())
                    good = arguments(2, build_payload())
                    self.assertEqual(run(good).returncode, 0)
                    self.assertNotEqual(link.readlink(), original)
                    self.assertTrue(original.is_dir(), 'Keep the previous version')
                    good[2] += '&unexpected=1'
                    self.assertNotEqual(run(good).returncode, 0)
                    self.assertFalse(list(city.glob('.install.*')), 'Clean failed stages')


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
