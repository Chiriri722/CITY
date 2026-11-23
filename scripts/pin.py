"""Print a scripts/agents.sh catalog line for an npm or PyPI release (maintainers only).

    python3 scripts/pin.py npm @google/gemini-cli          # latest
    python3 scripts/pin.py npm @google/gemini-cli 0.70.0
    python3 scripts/pin.py pypi aider-chat 0.86.2

Checksums come from the registry's own published metadata (npm "integrity",
PyPI "digests"), never from a local download. Review the output before use.
"""
import base64
import json
import re
import sys
import urllib.parse
import urllib.request


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def npm(package, version=None):
    if not re.fullmatch(r'(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*', package):
        raise ValueError('Invalid npm package name')
    meta = fetch('https://registry.npmjs.org/' + urllib.parse.quote(package, safe='@'))
    version = version or meta['dist-tags']['latest']
    dist = meta['versions'][version]['dist']
    algorithm, encoded = dist['integrity'].split('-', 1)
    if algorithm != 'sha512':
        raise ValueError(f'Unexpected integrity algorithm {algorithm}')
    expected = f"https://registry.npmjs.org/{package}/-/{package.split('/')[-1]}-{version}.tgz"
    if dist['tarball'] != expected:
        raise ValueError(f"Unexpected tarball URL {dist['tarball']}")
    return [f'npm_release {package} {version} {base64.b64decode(encoded).hex()}']


def pypi(project, version=None):
    meta = fetch(f'https://pypi.org/pypi/{urllib.parse.quote(project)}/'
                 + (f'{urllib.parse.quote(version)}/json' if version else 'json'))
    version = meta['info']['version']
    wheels = [f for f in meta['urls'] if f['packagetype'] == 'bdist_wheel' and not f['yanked']]
    pure = [f for f in wheels if f['filename'].endswith('-none-any.whl')]
    lines = []
    if pure:
        lines.append(f"wheel_release {version} {pure[0]['url']} {pure[0]['digests']['sha256']}")
    else:
        for arch in ('aarch64', 'x86_64'):
            found = [f for f in wheels if re.search(rf'manylinux[0-9_]*_{arch}\.whl$', f['filename'])]
            if not found:
                raise ValueError(f'No manylinux {arch} wheel for {project} {version}')
            lines.append(f"[{arch}] wheel_release {version} {found[0]['url']} "
                         f"{found[0]['digests']['sha256']}")
    return lines


if __name__ == '__main__':
    try:
        if len(sys.argv) not in (3, 4) or sys.argv[1] not in ('npm', 'pypi'):
            raise ValueError('Usage: pin.py npm|pypi NAME [VERSION]')
        source = npm if sys.argv[1] == 'npm' else pypi
        print('\n'.join(source(*sys.argv[2:])))
    except (OSError, ValueError, KeyError) as exc:
        sys.exit(f'pin: {exc}')
