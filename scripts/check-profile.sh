#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=24.04
if [[ "${1:-}" =~ ^(24\.04|26\.04)$ ]]; then version=$1; shift; fi
role=${1:-ci}
[[ $# -le 1 && "$role" =~ ^(dev|ci|cert)$ ]] || { echo 'Usage: bash scripts/check-profile.sh [24.04|26.04] [dev|ci|cert]' >&2; exit 2; }
image=${ACT4_PROFILE_IMAGE:-riscv-act4:ubuntu-$version-$role}
output=${ACT4_OUTPUT:-$root/logs/profile-$version-$role-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$output"
output=$(cd -- "$output" && pwd)
docker image inspect "$image" > "$output.image.json"
args=(--rm --network none --cpus 2 --memory 4g --memory-swap 6g --pids-limit 512
      --user root --entrypoint bash --env "OUTPUT_UID=$(id -u)" --env "OUTPUT_GID=$(id -g)"
      --env "EXPECTED_PROFILE=$role"
      --env "EXPECTED_UBUNTU_VERSION=$version"
      --mount "type=bind,src=$output,dst=/artifacts")
run_args=()
if [[ -n "${ACT4_SOURCE:-}" ]]; then
    [[ "$role" != cert ]] || { echo 'cert refuses ACT4_SOURCE' >&2; exit 2; }
    source_dir=$(cd -- "$ACT4_SOURCE" && pwd)
    args+=(--mount "type=bind,src=$source_dir,dst=/input,readonly")
    run_args+=(--source /input)
fi
if [[ "$role" == cert ]]; then
    : "${ACT4_SIGNING_KEY:?Set ACT4_SIGNING_KEY to an external private key}"
    : "${ACT4_VERIFICATION_KEY:?Set ACT4_VERIFICATION_KEY to its trusted public key}"
    private=$(realpath -- "$ACT4_SIGNING_KEY")
    public=$(realpath -- "$ACT4_VERIFICATION_KEY")
    test -f "$private" && test -f "$public"
    args+=(--read-only --tmpfs '/act4:rw,uid=1001,gid=1001,mode=0755'
           --tmpfs '/tmp:rw,mode=1777' --tmpfs '/run/keys:rw,mode=0700'
           --tmpfs '/home/riscv/.cache:rw,uid=1001,gid=1001,mode=0700'
           --mount "type=bind,src=$private,dst=/inputs/private.pem,readonly"
           --mount "type=bind,src=$public,dst=/inputs/public.pem,readonly")
    run_args+=(--signing-key /run/keys/private.pem --verification-key /run/keys/public.pem)
fi
docker run "${args[@]}" "$image" -c '
    set -e
    trap '\''chown -R "$OUTPUT_UID:$OUTPUT_GID" /artifacts'\'' EXIT
    actual_profile=$(cat /etc/riscv-act4-profile)
    test "$actual_profile" = "$EXPECTED_PROFILE" || { echo "Profile mismatch: expected $EXPECTED_PROFILE, got $actual_profile" >&2; exit 1; }
    actual_version=$(. /etc/os-release; echo "$VERSION_ID")
    test "$actual_version" = "$EXPECTED_UBUNTU_VERSION" || { echo "Ubuntu mismatch: expected $EXPECTED_UBUNTU_VERSION, got $actual_version" >&2; exit 1; }
    chown riscv:riscv /artifacts
    if [[ -f /inputs/private.pem ]]; then
        install -o riscv -g riscv -m 400 /inputs/private.pem /run/keys/private.pem
        install -o riscv -g riscv -m 400 /inputs/public.pem /run/keys/public.pem
        chown riscv:riscv /run/keys
    fi
    exec_args=(riscv-act4-run "$@")
    runuser -u riscv -- env HOME=/home/riscv "${exec_args[@]}"
' bash "${run_args[@]}"
printf 'Saved %s results: %s\n' "$role" "$output/results.json"
