#!/usr/bin/env bash
# CITY: common Termux/PRoot installer and launcher for coding agents.
set -euo pipefail
umask 077

die() { printf 'city: %s\n' "$*" >&2; exit 2; }
script_dir="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
[[ -r "$script_dir/scripts/agents.sh" ]] || die 'Missing scripts; keep the CITY checkout together.'
# shellcheck source=scripts/agents.sh
source "$script_dir/scripts/agents.sh"

usage() {
    cat <<HELP
CITY — coding agents in Termux via PRoot
  bash city.sh install <agent...|all>
  bash city.sh update [agent...|all]
  bash city.sh status
  bash city.sh <agent> [arguments...]
  bash city.sh --help
Agents: ${catalog[*]}
Set CITY_DISTRO=ubuntu (default) or debian for every command.
Run agents from a project beneath your Termux HOME.
install creates the distro once and reuses it afterwards.
update reuses the existing distro and updates installed agents only.
status reads metadata without installing packages or running agents.
HELP
}

# Validate agent names before any side effect; "all" must stand alone.
read_selection() {
    selection=("$@")
    [[ ${#selection[@]} != 0 ]] || selection=(all)
    local item
    for item in "${selection[@]}"; do
        if [[ "$item" == all ]]; then
            [[ ${#selection[@]} == 1 ]] || die 'Use "all" on its own.'
        else
            agent_info "$item"
        fi
    done
}

command="${1:---help}"
case "$command" in
    --help | -h | help) usage; exit 0 ;;
    install)
        [[ $# -ge 2 ]] || die "Usage: bash city.sh install <agent...|all>. Agents: ${catalog[*]}"
        shift
        read_selection "$@"
        ;;
    update) shift; read_selection "$@" ;;
    status) [[ $# == 1 ]] || die 'Usage: bash city.sh status' ;;
    *)
        # Only catalog names reach agent_info's case; anything else is rejected there.
        [[ "$command" =~ ^[a-z][a-z0-9-]*$ ]] || die "Unknown command: $command"
        agent_info "$command"
        shift
        ;;
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
node_version=v22.23.5
login=(proot-distro login --user root --isolated)

if [[ "$command" == install || "$command" == update || "$command" == status ]]; then
    [[ -r "$script_dir/scripts/guest-install.sh" && -r "$script_dir/scripts/environment.sh" ]] || die 'Missing scripts; keep the CITY checkout together.'
    # shellcheck source=scripts/environment.sh
    source "$script_dir/scripts/environment.sh"
    case "$(dpkg --print-architecture)" in
        aarch64 | arm64)
            arch=arm64
            node_sha=2babb9eb5264860d540849f4b064a6fbdebcdc323657d9d382ce23d313fd5e09
            ;;
        x86_64 | amd64)
            arch=x64
            node_sha=cdeb8670a0c81f51b4dc4ac61919f9b1ad917b304bf8221eb939570663d240f8
            ;;
        *) die 'Only 64-bit ARM and x86_64 Termux are supported.' ;;
    esac
    rootfs="$PREFIX/var/lib/proot-distro/containers/$distro/rootfs"
    owner="$rootfs/.city-owner"
    # Present only while CITY itself is creating the distro (see below).
    pending="$HOME/.local/share/city/creating-$distro"
    inspect_environment
    if [[ "$command" == status ]]; then
        revision="$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || printf unknown)"
        printf 'Checkout: %s\nRevision: %s\nDistro: %s\nRootfs: %s\nEnvironment: %s\n%s\n' \
            "$script_dir" "$revision" "$distro" "$rootfs" "$environment_state" "$environment_reason"
        [[ -z "$source_image" ]] || printf 'Original image: %s\n' "$source_image"
        if [[ "$environment_state" == unmanaged && -f "$pending" ]]; then
            printf 'An interrupted CITY install left this distro incomplete; install will recreate it.\n'
        fi
        [[ "$environment_state" != missing ]] || exit 0
        [[ "$environment_state" == managed || "$environment_state" == legacy ]] || exit 2
        status_code=0
        printf '\n%-12s %-10s %-24s %s\n' Agent State Recorded-version CITY-version
        for item in "${catalog[@]}"; do
            inspect_agent "$item"
            printf '%-12s %-10s %-24s %s\n' "$item" "$active_state" "$active_version" "$version"
            [[ "$active_state" != invalid ]] || status_code=2
        done
        exit "$status_code"
    fi
    if [[ "$command" == update ]]; then
        require_environment
        select_updates
        [[ ${#agents[@]} != 0 ]] || { printf 'city: no installed agents to update in %s. Use install to add one.\n' "$distro"; exit 0; }
    elif [[ "$environment_state" != missing && ! ( "$environment_state" == unmanaged && -f "$pending" ) ]]; then
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
    elif [[ -f "$pending" ]]; then
        inspect_environment
        if [[ "$environment_state" == unmanaged ]]; then
            # Only CITY writes this file, right before it creates the distro, and removes
            # it once the owner marker exists. So this is our own half-created distro.
            printf 'city: removing incomplete %s left by an interrupted install.\n' "$distro"
            proot-distro remove "$distro"
        fi
    fi
    if [[ ! -e "${rootfs%/rootfs}" && ! -L "${rootfs%/rootfs}" ]]; then
        [[ "$command" == install ]] || die 'update never creates a distro; use install first.'
        printf 'city: creating %s (checkout folder names do not create separate distros).\n' "$distro"
        download_dir="$(mktemp -d "$HOME/.local/share/city/rootfs.XXXXXX")"
        trap 'rm -rf -- "$download_dir"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        python3 "$script_dir/scripts/fetch-rootfs.py" "$image" "$arch" "$download_dir/rootfs.tar.gz"
        : >"$pending"
        proot-distro install --name "$distro" "$download_dir/rootfs.tar.gz"
        [[ -d "$rootfs" && ! -L "$rootfs" ]] || die 'PRoot-Distro did not create the expected rootfs.'
        printf '%s\n' "$image" >"$owner"
        rm -f -- "$pending"
        rm -rf -- "$download_dir"
        trap - EXIT INT TERM
    else
        printf 'city: reusing existing %s at %s\n' "$distro" "$rootfs"
    fi
    require_environment
    rm -f -- "$pending"
    record_environment
    if [[ "$command" == install ]]; then
        agents=("${selection[@]}")
        [[ "${selection[0]}" != all ]] || agents=("${catalog[@]}")
    fi
    # Refresh guest packages once per run; keep going if one agent fails.
    refresh_apt=1 failed=()
    for item in "${agents[@]}"; do
        agent_info "$item" "$arch"
        expected="$version"
        # Success means the guest exited 0 AND the host now sees the pinned release active.
        if "${login[@]}" "$distro" -- /bin/bash -s -- "$refresh_apt" \
            "$agent" "$binary" "$format" "$checksum" "$version" "$url" "$digest" "$member" \
            "$node_version" "$arch" "$node_sha" <"$script_dir/scripts/guest-install.sh" &&
            inspect_agent "$item" && [[ "$active_state" == managed && "$active_version" == "$expected" ]]; then
            refresh_apt=0
        else
            failed+=("$item")
            printf 'city: %s was not changed; its previous version (if any) stays active.\n' "$item" >&2
        fi
    done
    [[ ${#failed[@]} == 0 ]] || die "$command failed for: ${failed[*]}. Other agents completed in $distro."
    printf 'city: %s complete in %s. Run: bash city.sh <agent>\n' "$command" "$distro"
    exit 0
fi

command -v proot-distro >/dev/null || die "Install first: bash city.sh install $agent"
host_home="$(cd -- "$HOME" && pwd -P)"
cwd="$(pwd -P)"
case "$cwd" in
    "$host_home" | "$host_home/"*) guest_cwd="/root${cwd#"$host_home"}" ;;
    *) die 'Run from a directory beneath Termux HOME; shared storage is not mounted.' ;;
esac
agent_paths="$(printf '/opt/city/%s/bin:' "${catalog[@]}")"
# Foreground exec preserves terminal, stdin and exit status. PRoot owns child cleanup.
# Each agent runs with the Node it was verified with (.city-node), so a newer CITY
# checkout with a newer Node pin never breaks agents installed before "update".
# shellcheck disable=SC2016 # Expansion happens in the guest shell.
exec "${login[@]}" --shared-home "$distro" -- /bin/bash --noprofile --norc -c '
    set -eu
    node="$1" agent="$3" binary="$4"
    root="${binary%/bin/*}"
    if [ -f "$root/.city-node" ]; then
        recorded="$(cat "$root/.city-node")"
        case "$recorded" in v[0-9]*.[0-9]*.[0-9]*) node="$recorded" ;; esac
    fi
    node_bin="/opt/city/node-$node/bin"
    if [ ! -x "$node_bin/node" ]; then
        for candidate in /opt/city/node-v*/bin; do
            if [ -x "$candidate/node" ]; then node_bin="$candidate"; fi
        done
    fi
    export PATH="$root/bin:$node_bin:$5/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    export LANG="${LANG:-C.UTF-8}"
    # CITY pins and verifies releases; built-in self-updaters would bypass that.
    # Names and values as read by each release (Claude, Cline and CodeBuddy share the first).
    export DISABLE_AUTOUPDATER=1 OPENCODE_DISABLE_AUTOUPDATE=1 GROK_DISABLE_AUTOUPDATER=1 \
        COPILOT_AUTO_UPDATE=false AMP_SKIP_UPDATE_CHECK=1 CLINE_NO_AUTO_UPDATE=1 \
        AUGMENT_DISABLE_AUTO_UPDATE=1 QWEN_CODE_SKIP_UPDATE_CHECK_ONCE=true
    # Optional KEY=value lines (API keys etc.) from Termux ~/.config/city/env.
    if [ -f /root/.config/city/env ]; then set -a; . /root/.config/city/env; set +a; fi
    cd -- "$2" || exit 2
    shift 5
    test -x "$binary" || { echo "city: $agent is not installed; run: bash city.sh install $agent" >&2; exit 2; }
    exec "$binary" "$@"
' city "$node_version" "$guest_cwd" "$agent" "/opt/city/$agent/bin/$binary" "$agent_paths" "$@"
