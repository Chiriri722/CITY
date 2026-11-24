#!/usr/bin/env bash
# Internal: streamed to the dedicated distro, without sharing the host HOME.
# bash -s reads this script from stdin. Parse the whole body first, then run it with
# stdin detached, so no child (apt, npm, pip, an agent --version) can eat the script.
main() {
    set -euo pipefail
    umask 077
    [[ $# == 12 ]] || { echo 'city: invalid internal installer arguments' >&2; exit 2; }
    refresh_apt="$1" agent="$2" binary="$3" format="$4" checksum="$5" version="$6" url="$7" digest="$8"
    member="$9" node_version="${10}" arch="${11}" node_sha="${12}"
    version_pattern='[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.]*)?'
    [[ "$refresh_apt" == 0 || "$refresh_apt" == 1 ]]
    [[ "$agent" =~ ^[a-z][a-z0-9-]*$ && "$binary" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
    [[ "$version" =~ ^$version_pattern$ && "$node_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
    [[ "$node_sha" =~ ^[0-9a-f]{64}$ ]]
    [[ "$arch" == arm64 || "$arch" == x64 ]]
    case "$checksum" in
        sha256) [[ "$digest" =~ ^[0-9a-f]{64}$ ]] ;;
        sha512) [[ "$digest" =~ ^[0-9a-f]{128}$ ]] ;;
        *) exit 2 ;;
    esac
    # Independent URL checks: npm and PyPI by shape, native downloads per vendor.
    v="${version//./\\.}"
    case "$format" in
        npm) [[ "$url" =~ ^https://registry\.npmjs\.org/(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*/-/[a-z0-9][a-z0-9._-]*-$v\.tgz$ ]] ;;
        wheel) [[ "$url" =~ ^https://files\.pythonhosted\.org/packages/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{60}/[A-Za-z0-9_]+-$v-[A-Za-z0-9_.-]+\.whl$ ]] ;;
        archive | binary)
            case "$agent:$arch" in
                antigravity:arm64) expected="https://storage.googleapis.com/antigravity-public/antigravity-cli/$version-4582356770750464/linux-arm/cli_linux_arm64.tar.gz" ;;
                antigravity:x64) expected="https://storage.googleapis.com/antigravity-public/antigravity-cli/$version-4582356770750464/linux-x64/cli_linux_x64.tar.gz" ;;
                jules:arm64) expected="https://storage.googleapis.com/jules-cli/v$version/jules_external_v${version}_linux_arm64.tar.gz" ;;
                jules:x64) expected="https://storage.googleapis.com/jules-cli/v$version/jules_external_v${version}_linux_amd64.tar.gz" ;;
                kiro:arm64) expected="https://desktop-release.q.us-east-1.amazonaws.com/$version/kirocli-aarch64-linux.tar.gz" ;;
                kiro:x64) expected="https://desktop-release.q.us-east-1.amazonaws.com/$version/kirocli-x86_64-linux.tar.gz" ;;
                muse:arm64) expected="https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=$version&file=muse-aarch64-linux" ;;
                muse:x64) expected="https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=$version&file=muse-x86-linux" ;;
                *) exit 2 ;;
            esac
            [[ "$url" == "$expected" ]]
            ;;
        *) exit 2 ;;
    esac
    if [[ "$format" == archive ]]; then
        [[ "$member" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "/$member/" != */../* ]]
    else
        [[ "$member" == - ]]
    fi

    export DEBIAN_FRONTEND=noninteractive
    if [[ "$refresh_apt" == 1 ]]; then
        apt-get update
        apt-get install -y --no-install-recommends ca-certificates curl xz-utils git ripgrep libstdc++6 \
            python3 python-is-python3 python3-pip python3-venv python3-cryptography
    fi
    mkdir -p /opt/city
    stage="$(mktemp -d /opt/city/.install.XXXXXX)"
    trap 'rm -rf -- "$stage"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    download() { curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 20 --max-time 1800 "$1" -o "$2"; }

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
    # Same PATH shape as the launcher: this agent first, then the Node it was verified with.
    target="/opt/city/$agent-$version"
    export PATH="$target/bin:$node_root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    link="/opt/city/$agent"
    if [[ -e "$link" || -L "$link" ]]; then
        [[ -L "$link" ]] || { echo "city: refusing unmanaged $link" >&2; exit 2; }
        previous="$(readlink -- "$link")"
        [[ "$previous" =~ ^/opt/city/$agent-$version_pattern$ ]] || exit 2
        [[ -f "$previous/.city-sha512" || -f "$previous/.city-sha256" ]] || exit 2
    fi
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        # npm needs a .tgz name for a local tarball; pip needs the real wheel filename.
        case "$format" in
            npm) payload="$stage/payload.tgz" ;;
            wheel) payload="$stage/${url##*/}" ;;
            *) payload="$stage/payload" ;;
        esac
        download "$url" "$payload"
        printf '%s  %s\n' "$digest" "$payload" | "${checksum}sum" -c -
        mkdir -p "$stage/agent/bin"
        case "$format" in
            npm)
                npm install --global --prefix "$stage/agent" --registry=https://registry.npmjs.org \
                    --include=optional --no-audit --no-fund "$payload"
                ;;
            archive)
                mkdir "$stage/unpack"
                tar -xzf "$payload" -C "$stage/unpack" --no-same-owner -- "$member"
                [[ -f "$stage/unpack/$member" && ! -L "$stage/unpack/$member" ]]
                install -m 755 "$stage/unpack/$member" "$stage/agent/bin/$binary"
                ;;
            binary) install -m 755 "$payload" "$stage/agent/bin/$binary" ;;
            wheel)
                # A venv keeps each Python agent's dependencies out of the distro and other agents.
                python3 -m venv "$stage/agent/venv"
                "$stage/agent/venv/bin/python" -m pip install --no-cache-dir --disable-pip-version-check \
                    --no-input --prefer-binary "$payload"
                [[ -f "$stage/agent/venv/bin/$binary" ]]
                # Run the console script through the venv interpreter, so the directory can move.
                # shellcheck disable=SC2016 # Expanded when the wrapper runs.
                printf '%s\n' '#!/bin/sh' \
                    'root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)" || exit 2' \
                    "exec \"\$root/venv/bin/python\" \"\$root/venv/bin/$binary\" \"\$@\"" \
                    >"$stage/agent/bin/$binary"
                chmod 755 "$stage/agent/bin/$binary"
                ;;
        esac
        "$stage/agent/bin/$binary" --version
        printf '%s\n' "$digest" >"$stage/agent/.city-$checksum"
        printf '%s\n' "$node_version" >"$stage/agent/.city-node"
        mv -T -- "$stage/agent" "$target"
    fi
    [[ -d "$target" && ! -L "$target" && "$(cat "$target/.city-$checksum")" == "$digest" ]]
    "$target/bin/$binary" --version
    if [[ ! -f "$target/.city-node" || "$(cat "$target/.city-node")" != "$node_version" ]]; then
        # Existing release, new pinned Node: it just passed the startup check with it.
        printf '%s\n' "$node_version" >"$stage/node-marker"
        mv -Tf -- "$stage/node-marker" "$target/.city-node"
    fi
    ln -s -- "$target" "$stage/current"
    # Only switch this agent after download, integrity and startup checks succeed.
    mv -Tf -- "$stage/current" "$link"
    printf 'city: %s %s ready\n' "$agent" "$version"
}
main "$@" </dev/null
