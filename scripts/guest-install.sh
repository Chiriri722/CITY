#!/usr/bin/env bash
# Internal: streamed to the dedicated distro, without sharing the host HOME.
set -euo pipefail
umask 077
[[ $# == 7 ]] || { echo 'city: invalid internal installer arguments' >&2; exit 2; }
agent="$1" version="$2" url="$3" digest="$4" node_version="$5" arch="$6" node_sha="$7"
[[ "$agent" == codex || "$agent" == opencode ]]
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$node_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$digest" =~ ^[0-9a-f]{128}$ && "$node_sha" =~ ^[0-9a-f]{64}$ ]]
[[ "$arch" == arm64 || "$arch" == x64 ]]
case "$url" in
    "https://registry.npmjs.org/@openai/codex/-/codex-$version.tgz" | "https://registry.npmjs.org/opencode-ai/-/opencode-ai-$version.tgz") ;;
    *) exit 2 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl xz-utils git ripgrep libstdc++6 \
    python3 python-is-python3 python3-pip python3-venv python3-cryptography
mkdir -p /opt/city
stage="$(mktemp -d /opt/city/.install.XXXXXX)"
trap 'rm -rf -- "$stage"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
download() { curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 20 --max-time 600 "$1" -o "$2"; }

node_root="/opt/city/node-$node_version"
if [[ ! -e "$node_root" && ! -L "$node_root" ]]; then
    download "https://nodejs.org/dist/$node_version/node-$node_version-linux-$arch.tar.xz" "$stage/node.tar.xz"
    printf '%s  %s\n' "$node_sha" "$stage/node.tar.xz" | sha256sum -c -
    mkdir "$stage/node"
    tar -xJf "$stage/node.tar.xz" -C "$stage/node" --strip-components=1
    "$stage/node/bin/node" --version
    printf '%s\n' "$node_sha" >"$stage/node/.city-sha256"
    mv -T -- "$stage/node" "$node_root"
fi
[[ -d "$node_root" && ! -L "$node_root" && "$(cat "$node_root/.city-sha256")" == "$node_sha" ]]
export PATH="$node_root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
target="/opt/city/$agent-$version"
link="/opt/city/$agent"
if [[ -e "$link" || -L "$link" ]]; then
    [[ -L "$link" ]] || { echo "city: refusing unmanaged $link" >&2; exit 2; }
    previous="$(readlink -- "$link")"
    [[ "$previous" =~ ^/opt/city/$agent-[0-9]+\.[0-9]+\.[0-9]+$ && -f "$previous/.city-sha512" ]] || exit 2
fi
if [[ ! -e "$target" && ! -L "$target" ]]; then
    download "$url" "$stage/agent.tgz"
    printf '%s  %s\n' "$digest" "$stage/agent.tgz" | sha512sum -c -
    npm install --global --prefix "$stage/agent" --registry=https://registry.npmjs.org \
        --include=optional --no-audit --no-fund "$stage/agent.tgz"
    "$stage/agent/bin/$agent" --version
    printf '%s\n' "$digest" >"$stage/agent/.city-sha512"
    mv -T -- "$stage/agent" "$target"
fi
[[ -d "$target" && ! -L "$target" && "$(cat "$target/.city-sha512")" == "$digest" ]]
"$target/bin/$agent" --version
ln -s -- "$target" "$stage/current"
# Only switch this agent after download, integrity and startup checks succeed.
mv -Tf -- "$stage/current" "$link"
printf 'city: %s %s ready\n' "$agent" "$version"
