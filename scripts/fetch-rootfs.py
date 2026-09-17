"""Fetch a digest-pinned, single-layer Docker Hub rootfs using only the stdlib.

PRoot-Distro 5.8.0 cannot parse image@sha256 references. Its local archive
installer works, so verify the index, platform manifest and layer before use.
"""
import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme != 'https':
            raise ValueError('Refusing non-HTTPS redirect')
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if urllib.parse.urlsplit(req.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
            redirected.remove_header('Authorization')
        return redirected


def verify(data, digest):
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise ValueError('Invalid SHA-256 digest')
    if 'sha256:' + hashlib.sha256(data).hexdigest() != digest:
        raise ValueError('Rootfs metadata checksum mismatch')


def download(image, arch, destination):
    match = re.fullmatch(r'(ubuntu|debian)@(sha256:[0-9a-f]{64})', image)
    if not match or arch not in ('arm64', 'x64'):
        raise ValueError('Expected a pinned Ubuntu/Debian image and arm64/x64')
    repo, index_digest = 'library/' + match[1], match[2]
    opener = urllib.request.build_opener(HTTPSRedirect())
    auth_url = 'https://auth.docker.io/token?' + urllib.parse.urlencode({
        'service': 'registry.docker.io', 'scope': f'repository:{repo}:pull'})
    with opener.open(auth_url, timeout=60) as response:
        token = json.load(response)['token']
    base = f'https://registry-1.docker.io/v2/{repo}/'
    headers = {'Authorization': 'Bearer ' + token, 'Accept': ', '.join((
        'application/vnd.oci.image.index.v1+json',
        'application/vnd.oci.image.manifest.v1+json',
        'application/vnd.docker.distribution.manifest.list.v2+json',
        'application/vnd.docker.distribution.manifest.v2+json'))}

    def manifest(digest):
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
            raise ValueError('Invalid manifest digest')
        request = urllib.request.Request(base + 'manifests/' + digest, headers=headers)
        with opener.open(request, timeout=60) as response:
            data = response.read(1024 * 1024)
        verify(data, digest)
        return json.loads(data)

    index = manifest(index_digest)
    platform = 'amd64' if arch == 'x64' else arch
    matches = [entry for entry in index['manifests']
               if entry.get('platform', {}).get('os') == 'linux'
               and entry['platform'].get('architecture') == platform]
    if len(matches) != 1:
        raise ValueError(f'Expected one linux/{platform} manifest')
    layers = manifest(matches[0]['digest'])['layers']
    # ponytail: the pinned base images have one gzip layer; reject multi-layer images.
    if len(layers) != 1 or layers[0]['mediaType'] not in (
            'application/vnd.oci.image.layer.v1.tar+gzip',
            'application/vnd.docker.image.rootfs.diff.tar.gzip'):
        raise ValueError('Expected a single gzip rootfs layer; refusing unsupported image')
    layer = layers[0]
    digest = layer['digest']
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise ValueError('Invalid layer digest')
    request = urllib.request.Request(base + 'blobs/' + digest, headers=headers)
    checksum, size = hashlib.sha256(), 0
    with opener.open(request, timeout=60) as response, Path(destination).open('xb') as output:
        while chunk := response.read(1024 * 1024):
            checksum.update(chunk)
            size += len(chunk)
            output.write(chunk)
    if 'sha256:' + checksum.hexdigest() != digest or size != layer['size']:
        raise ValueError('Rootfs layer checksum/size mismatch; archive must not be installed')
    print(f'city: verified {image} linux/{platform} rootfs', flush=True)


if __name__ == '__main__':
    try:
        if len(sys.argv) != 4:
            raise ValueError('Usage: fetch-rootfs.py IMAGE ARCH OUTPUT')
        download(*sys.argv[1:])
    except (OSError, ValueError, KeyError, TypeError) as exc:
        sys.exit(f'city: rootfs download failed: {exc}')
