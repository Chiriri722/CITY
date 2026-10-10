#!/usr/bin/env bash
# CITY: common Termux/PRoot installer and launcher for coding agents.
set -euo pipefail
umask 077

die() { printf 'city: %s\n' "$*" >&2; exit 2; }
usage() {
    cat <<'HELP'
CITY — coding agents in Termux via PRoot
  bash city.sh install <codex|opencode|antigravity|grok|muse|all>
  bash city.sh update [codex|opencode|antigravity|grok|muse|all]
  bash city.sh status
  bash city.sh codex [arguments...]
  bash city.sh opencode [arguments...]
  bash city.sh antigravity [arguments...]   (agy)
  bash city.sh grok [arguments...]          (Grok Build)
  bash city.sh muse [arguments...]          (Muse Code)
  bash city.sh --help
Set CITY_DISTRO=ubuntu (default) or debian for every command.
Run agents from a project beneath your Termux HOME.
update reuses the existing distro and updates installed agents only.
status reads metadata without installing packages or running agents.
HELP
}

# Pin official releases. The optional architecture is needed only at install time.
agent_info() {
    agent="$1"
    binary="$agent"
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
        antigravity)
            binary=agy
            version=1.3.1
            if [[ "${2:-x64}" == arm64 ]]; then
                url="https://storage.googleapis.com/antigravity-public/antigravity-cli/$version-4582356770750464/linux-arm/cli_linux_arm64.tar.gz"
                digest=c41b8cd8c526eb043fa0b019377ab8109190b547624f17f5255868ace79cd8e9195a60ac7b89478101127effbe049341c4108ed0ead4b160968704a8b79d8799
            else
                url="https://storage.googleapis.com/antigravity-public/antigravity-cli/$version-4582356770750464/linux-x64/cli_linux_x64.tar.gz"
                digest=3b8349d72678795baf8788481815e20d7acf3b80f9d2f867a607e712bc6be7fb18fd7d4fcf3aeee4ae593b0f469684c6d3497524f10a4c426a1a2bdec20b1f68
            fi
            ;;
        grok)
            version=1.0.46
            url="https://registry.npmjs.org/@xai-official/grok/-/grok-$version.tgz"
            digest=a973b89b224501008864d8cc25601a2744d35208b65ab4299d862dadd77d850f1361eccf1f4b25487058831a9e765c2070755da818a20d750b1e421d043ce4c9
            ;;
        muse)
            version=1.4.3-R5018.1
            if [[ "${2:-x64}" == arm64 ]]; then
                url="https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=$version&file=muse-aarch64-linux"
                digest=6426c76a0081f20d60f6cad03308a147d79ce45758f1a89fd2713253cf475497
            else
                url="https://lookaside.facebook.com/lookaside/muse/download/?channel=muse&version=$version&file=muse-x86-linux"
                digest=e671790882bc88d65edb4ae0f713becf378ebf91011034ab75abebe3592dde4f
            fi
            ;;
        *) die "Unsupported agent: $agent" ;;
    esac
}

command="${1:---help}"
catalog=(codex opencode antigravity grok muse)
case "$command" in
    --help | -h | help) usage; exit 0 ;;
    install)
        [[ $# == 2 ]] || die 'Usage: bash city.sh install <codex|opencode|antigravity|grok|muse|all>'
        selection="$2"
        [[ "$selection" == all ]] || agent_info "$selection"
        ;;
    update)
        [[ $# -le 2 ]] || die 'Usage: bash city.sh update [agent|all]'
        selection="${2:-all}"
        [[ "$selection" == all ]] || agent_info "$selection"
        ;;
    status) [[ $# == 1 ]] || die 'Usage: bash city.sh status' ;;
    codex | opencode | antigravity | grok | muse) agent_info "$command"; shift ;;
    *) die "Unknown command: $command" ;;
esac

case "${CITY_DISTRO:-ubuntu}" in
    ubuntu) image=ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517 ;;
    debian) image=debian@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241 ;;
    *) die 'CITY_DISTRO must be ubuntu or debian.' ;;
esac
distro_id="${CITY_DISTRO:-ubuntu}"
# Known original images for migration from the single-line owner marker.
case "$distro_id" in
    ubuntu) release=24.04; legacy_image=ubuntu@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517 ;;
    debian) release=12; legacy_image=debian@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241 ;;
esac
[[ "${PREFIX:-}" =~ ^/data/data/com\.termux[^/]*/files/usr/?$ ]] || die 'Run this command inside Termux.'
PREFIX="${PREFIX%/}"
distro="city-$distro_id"
node_version=v22.23.2
login=(proot-distro login --user root --isolated)

if [[ "$command" == install || "$command" == update || "$command" == status ]]; then
    script_dir="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
    [[ -r "$script_dir/scripts/guest-install.sh" && -r "$script_dir/scripts/environment.sh" ]] || die 'Missing scripts; keep the CITY checkout together.'
    # shellcheck source=scripts/environment.sh
    source "$script_dir/scripts/environment.sh"
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
    rootfs="$PREFIX/var/lib/proot-distro/containers/$distro/rootfs"
    owner="$rootfs/.city-owner"
    inspect_environment
    if [[ "$command" == status ]]; then
        revision="$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || printf unknown)"
        printf 'Checkout: %s\nRevision: %s\nDistro: %s\nRootfs: %s\nEnvironment: %s\n%s\n' \
            "$script_dir" "$revision" "$distro" "$rootfs" "$environment_state" "$environment_reason"
        [[ -z "$source_image" ]] || printf 'Original image: %s\n' "$source_image"
        [[ "$environment_state" != missing ]] || exit 0
        [[ "$environment_state" == managed || "$environment_state" == legacy ]] || exit 2
        status_code=0
        printf '\n%-14s %-10s %-20s %s\n' Agent State Recorded-version CITY-version
        for item in "${catalog[@]}"; do
            inspect_agent "$item"
            printf '%-14s %-10s %-20s %s\n' "$item" "$active_state" "$active_version" "$version"
            [[ "$active_state" != invalid ]] || status_code=2
        done
        exit "$status_code"
    fi
    if [[ "$command" == update ]]; then
        require_environment
        select_updates
        [[ ${#agents[@]} != 0 ]] || { printf 'city: no installed agents to update in %s. Use install to add one.\n' "$distro"; exit 0; }
    elif [[ "$environment_state" != missing ]]; then
        require_environment
    fi
    if [[ "$command" == install ]]; then
        pkg update -y
        pkg install -y proot-distro util-linux python
    fi
    pd_version="$(dpkg-query -W -f='${Version}' proot-distro)"
    dpkg --compare-versions "$pd_version" ge 5.0.0 || die 'PRoot-Distro 5 or newer is required.'
    mkdir -p "$HOME/.local/share/city"
    # ponytail: one install lock; split by distro only if concurrent installs matter.
    exec 9>"$HOME/.local/share/city/install.lock"
    flock -n 9 || die 'Another CITY installation is running.'
    # Recheck under the shared lock before mutating any existing environment.
    if [[ "$command" == update ]]; then
        require_environment
        select_updates
    fi
    if [[ ! -e "${rootfs%/rootfs}" && ! -L "${rootfs%/rootfs}" ]]; then
        [[ "$command" == install ]] || die 'update never creates a distro; use install first.'
        printf 'city: creating %s (checkout folder names do not create separate distros).\n' "$distro"
        download_dir="$(mktemp -d "$HOME/.local/share/city/rootfs.XXXXXX")"
        trap 'rm -rf -- "$download_dir"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        python3 "$script_dir/scripts/fetch-rootfs.py" "$image" "$arch" "$download_dir/rootfs.tar.gz"
        proot-distro install --name "$distro" "$download_dir/rootfs.tar.gz"
        [[ -d "$rootfs" && ! -L "$rootfs" ]] || die 'PRoot-Distro did not create the expected rootfs.'
        printf '%s\n' "$image" >"$owner"
        rm -rf -- "$download_dir"
        trap - EXIT INT TERM
    else
        printf 'city: reusing existing %s at %s\n' "$distro" "$rootfs"
    fi
    require_environment
    record_environment
    if [[ "$command" == install ]]; then
        agents=("$selection")
        [[ "$selection" != all ]] || agents=("${catalog[@]}")
    fi
    for item in "${agents[@]}"; do
        agent_info "$item" "$arch"
        "${login[@]}" "$distro" -- /bin/bash -s -- \
            "$agent" "$version" "$url" "$digest" "$node_version" "$arch" "$node_sha" \
            <"$script_dir/scripts/guest-install.sh"
    done
    printf 'city: %s complete in %s. Run: bash city.sh <codex|opencode|antigravity|grok|muse>\n' "$command" "$distro"
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
    export PATH="/opt/city/node-$1/bin:/opt/city/codex/bin:/opt/city/opencode/bin:/opt/city/antigravity/bin:/opt/city/grok/bin:/opt/city/muse/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    cd -- "$2" || exit 2
    binary="$3"
    shift 3
    test -x "$binary" || { echo "city: agent missing; run install first." >&2; exit 2; }
    exec "$binary" "$@"
' city "$node_version" "$guest_cwd" "/opt/city/$agent/bin/$binary" "$@"
