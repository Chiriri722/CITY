#!/usr/bin/env bash
# CITY: common Termux/PRoot installer and launcher for coding agents.
set -euo pipefail
umask 077

die() { printf 'city: %s\n' "$*" >&2; exit 2; }
usage() {
    cat <<'HELP'
CITY — coding agents in Termux via PRoot
  bash city.sh install <codex|opencode|all>
  bash city.sh codex [arguments...]
  bash city.sh opencode [arguments...]
  bash city.sh --help
Set CITY_DISTRO=ubuntu (default) or debian for every command.
Run agents from a project beneath your Termux HOME.
HELP
}

# Pin each agent's official npm tarball. Add future agents here and to dispatch.
agent_info() {
    agent="$1"
    case "$agent" in
        codex)
            version=0.154.0
            url="https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz"
            digest=155ff1d4e1d762ffe27e37f79978fd4e14d301671464de9c18845046147190a34e3ee226bb5596d1cf1ebf5bd4904f57187f747449d81b5b418c8931462920d3
            ;;
        opencode)
            version=1.18.31
            url="https://registry.npmjs.org/opencode-ai/-/opencode-ai-${version}.tgz"
            digest=27de5f79e7de5b0b486b0de2af1efa5a3cd6720417c66b8798356986fb397a9f57df47c127a4fa6c5870e748bd2b1e74306ff13e7e70da969f5c87cdb5daf2f7
            ;;
        *) die "Unsupported agent: $agent" ;;
    esac
}

command="${1:---help}"
case "$command" in
    --help | -h | help) usage; exit 0 ;;
    install)
        [[ $# == 2 ]] || die 'Usage: bash city.sh install <codex|opencode|all>'
        selection="$2"
        [[ "$selection" == all ]] || agent_info "$selection"
        ;;
    codex | opencode) agent_info "$command"; shift ;;
    *) die "Unknown command: $command" ;;
esac

case "${CITY_DISTRO:-ubuntu}" in
    ubuntu) image=ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517 ;;
    debian) image=debian@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241 ;;
    *) die 'CITY_DISTRO must be ubuntu or debian.' ;;
esac
[[ "${PREFIX:-}" =~ ^/data/data/com\.termux[^/]*/files/usr/?$ ]] || die 'Run this command inside Termux.'
distro="city-${CITY_DISTRO:-ubuntu}"
node_version=v22.23.2
login=(proot-distro login --user root --isolated)

if [[ "$command" == install ]]; then
    script_dir="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
    [[ -r "$script_dir/scripts/guest-install.sh" ]] || die 'Missing scripts/guest-install.sh; keep the CITY checkout together.'
    case "$(dpkg --print-architecture)" in
        aarch64 | arm64)
            arch=arm64
            node_sha=fff4078c5def658577f92c88db7db3bc0072924bfb93fe52c1e744a54e94abb8
            ;;
        x86_64 | amd64)
            arch=x64
            node_sha=d60acfe00a2932254bb0ad20e01b0d74397a0875595de719654b214f4b03f307
            ;;
        *) die 'Only 64-bit ARM and x86_64 Termux are supported.' ;;
    esac
    pkg update -y
    pkg install -y proot-distro util-linux
    pd_version="$(dpkg-query -W -f='${Version}' proot-distro)"
    dpkg --compare-versions "$pd_version" ge 5.0.0 || die 'PRoot-Distro 5 or newer is required.'
    mkdir -p "$HOME/.local/share/city"
    # ponytail: one install lock; split by distro only if concurrent installs matter.
    exec 9>"$HOME/.local/share/city/install.lock"
    flock -n 9 || die 'Another CITY installation is running.'
    rootfs="$PREFIX/var/lib/proot-distro/containers/$distro/rootfs"
    owner="$rootfs/.city-owner"
    if [[ ! -e "${rootfs%/rootfs}" && ! -L "${rootfs%/rootfs}" ]]; then
        proot-distro install --name "$distro" "$image"
        [[ -d "$rootfs" && ! -L "$rootfs" ]] || die 'PRoot-Distro did not create the expected rootfs.'
        printf '%s\n' "$image" >"$owner"
    fi
    [[ -d "$rootfs" && ! -L "$rootfs" && -f "$owner" && ! -L "$owner" && "$(cat -- "$owner")" == "$image" ]] || die "Refusing unmanaged distro $distro. Choose the other CITY_DISTRO or inspect it manually."
    agents=("$selection")
    [[ "$selection" != all ]] || agents=(codex opencode)
    for item in "${agents[@]}"; do
        agent_info "$item"
        "${login[@]}" "$distro" -- /bin/bash -s -- \
            "$agent" "$version" "$url" "$digest" "$node_version" "$arch" "$node_sha" \
            <"$script_dir/scripts/guest-install.sh"
    done
    printf 'Installed in %s. Run: bash city.sh <codex|opencode>\n' "$distro"
    exit 0
fi

command -v proot-distro >/dev/null || die "Install first: bash city.sh install $agent"
host_home="$(cd -- "$HOME" && pwd -P)"
cwd="$(pwd -P)"
case "$cwd" in
    "$host_home" | "$host_home/"*) guest_cwd="/root${cwd#"$host_home"}" ;;
    *) die 'Run from a directory beneath Termux HOME; shared storage is not mounted.' ;;
esac
# Foreground exec preserves terminal, stdin and exit status. PRoot owns child cleanup.
# shellcheck disable=SC2016 # Expansion happens in the guest shell.
exec "${login[@]}" --shared-home "$distro" -- /bin/bash --noprofile --norc -c '
    set -eu
    export PATH="/opt/city/node-$1/bin:/opt/city/codex/bin:/opt/city/opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    cd -- "$2" || exit 2
    binary="$3"
    shift 3
    test -x "$binary" || { echo "city: agent missing; run install first." >&2; exit 2; }
    exec "$binary" "$@"
' city "$node_version" "$guest_cwd" "/opt/city/$agent/bin/$agent" "$@"
