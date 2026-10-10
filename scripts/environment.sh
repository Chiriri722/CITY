#!/usr/bin/env bash
# Sourced by city.sh. Inspect metadata without entering the guest or running agents.
# shellcheck disable=SC2154

root_file() {
    local resolved
    resolved="$(realpath -e -- "$1" 2>/dev/null)" || return 1
    [[ "$resolved" == "$root_real/"* && -f "$resolved" ]] || return 1
    printf '%s\n' "$resolved"
}

inspect_environment() {
    environment_state=missing
    environment_reason='Run install to create this CITY environment.'
    source_image=''
    [[ -e "${rootfs%/rootfs}" || -L "${rootfs%/rootfs}" ]] || return 0
    environment_state=unmanaged
    environment_reason='Rootfs or CITY owner marker is missing, invalid, or a symlink.'
    [[ -d "$rootfs" && ! -L "$rootfs" && ! -L "${rootfs%/rootfs}" && -f "$owner" && ! -L "$owner" ]] || return 0
    local records marker_state os_file bash_file magic machine os_id os_version
    mapfile -t records <"$owner"
    if [[ ${#records[@]} == 1 ]]; then
        # Keep this legacy provenance when the default download image changes.
        [[ "${records[0]}" == "$legacy_image" || "${records[0]}" == "$image" ]] || return 0
        source_image="${records[0]}"
        marker_state=legacy
    elif [[ ${#records[@]} == 5 && "${records[0]}" == CITY_ENV_V1 ]]; then
        [[ "${records[4]}" =~ ^$distro_id@sha256:[0-9a-f]{64}$ ]] || return 0
        source_image="${records[4]}"
        environment_state=incompatible
        environment_reason='Recorded OS release or architecture does not match this CITY runtime.'
        [[ "${records[1]}" == "$distro_id" && "${records[2]}" == "$release" && "${records[3]}" == "$arch" ]] || return 0
        marker_state=managed
    else
        return 0
    fi
    environment_state=incompatible
    environment_reason='Guest OS release or Bash architecture does not match this CITY runtime.'
    root_real="$(realpath -e -- "$rootfs")"
    os_file="$(root_file "$rootfs/etc/os-release")" || return 0
    # Parse data only: never source a guest-owned os-release file on the host.
    os_id="$(sed -n 's/^ID=//p' "$os_file" | tr -d "\"'")"
    os_version="$(sed -n 's/^VERSION_ID=//p' "$os_file" | tr -d "\"'")"
    [[ "$os_id" == "$distro_id" && "$os_version" == "$release" ]] || return 0
    bash_file="$(root_file "$rootfs/usr/bin/bash")" || bash_file="$(root_file "$rootfs/bin/bash")" || return 0
    magic="$(od -An -tx1 -N6 -- "$bash_file" | tr -d ' \n')"
    machine="$(od -An -tx1 -j18 -N2 -- "$bash_file" | tr -d ' \n')"
    [[ "$magic" == 7f454c460201 ]] || return 0
    [[ "$arch:$machine" == x64:3e00 || "$arch:$machine" == arm64:b700 ]] || return 0
    environment_state="$marker_state"
    environment_reason='Compatible CITY environment; existing rootfs will be reused.'
}

require_environment() {
    inspect_environment
    [[ "$environment_state" == managed || "$environment_state" == legacy ]] ||
        die "$distro: $environment_state. $environment_reason No environment was replaced."
}

record_environment() {
    [[ "$environment_state" == legacy ]] || return 0
    local temporary
    temporary="$(mktemp "$rootfs/.city-owner.XXXXXX")"
    if printf '%s\n' CITY_ENV_V1 "$distro_id" "$release" "$arch" "$source_image" >"$temporary" &&
        mv -Tf -- "$temporary" "$owner"; then
        printf 'city: recorded environment metadata; preserved original image %s\n' "$source_image"
    else
        rm -f -- "$temporary"
        die 'Could not record CITY environment metadata.'
    fi
}

inspect_agent() {
    agent_info "$1"
    active_state=absent active_version='-'
    local link target pattern receipt receipt_file executable target_real
    link="$rootfs/opt/city/$agent"
    [[ -e "$link" || -L "$link" ]] || return 0
    active_state=invalid
    [[ -L "$link" ]] || return 0
    target="$(readlink -- "$link")"
    pattern='[0-9]+\.[0-9]+\.[0-9]+'
    [[ "$agent" != muse ]] || pattern+='-R[0-9]+(\.[0-9]+)?'
    [[ "$target" =~ ^/opt/city/$agent-($pattern)$ ]] || return 0
    active_version="${BASH_REMATCH[1]}"
    [[ -d "$rootfs$target" && ! -L "$rootfs$target" ]] || return 0
    target_real="$(realpath -e -- "$rootfs$target")"
    [[ "$target_real" == "$root_real/opt/city/$agent-$active_version" ]] || return 0
    receipt=.city-sha512
    [[ "$agent" != muse ]] || receipt=.city-sha256
    [[ ! -L "$rootfs$target/$receipt" ]] || return 0
    receipt_file="$(root_file "$rootfs$target/$receipt")" || return 0
    receipt="$(cat -- "$receipt_file")"
    if [[ "$agent" == muse ]]; then
        [[ "$receipt" =~ ^[0-9a-f]{64}$ ]] || return 0
    else
        [[ "$receipt" =~ ^[0-9a-f]{128}$ ]] || return 0
    fi
    executable="$(root_file "$rootfs$target/bin/$binary")" || return 0
    [[ -x "$executable" ]] || return 0
    active_state=managed
}

select_updates() {
    agents=()
    local item candidates
    candidates=("$selection")
    [[ "$selection" != all ]] || candidates=("${catalog[@]}")
    for item in "${candidates[@]}"; do
        inspect_agent "$item"
        case "$active_state" in
            managed) agents+=("$item") ;;
            invalid) die "Invalid CITY installation for $item; inspect it before updating." ;;
            absent) [[ "$selection" == all ]] || die "$item is not installed. Run: bash city.sh install $item" ;;
        esac
    done
}
