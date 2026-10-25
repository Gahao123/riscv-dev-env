#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:-24.04}
if [[ $# -gt 1 || ! "$version" =~ ^(24\.04|26\.04)$ ]]; then
    echo 'Usage: bash scripts/check-act4.sh [24.04|26.04]' >&2
    exit 2
fi
image=${ACT4_IMAGE:-riscv-act4:ubuntu-$version}
output=${ACT4_OUTPUT:-$root/logs/act4-$version-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$output"
output=$(cd -- "$output" && pwd)
docker image inspect "$image" > "$output/image-inspect.json"
# The image's default user owns a new output tree. No dependency downloads are allowed.
docker run --rm --network none --cpus 2 --memory 4g --memory-swap 6g --pids-limit 512 \
    --env "ACT4_JOBS=${ACT4_JOBS:-2}" \
    --env "OUTPUT_UID=$(id -u)" --env "OUTPUT_GID=$(id -g)" \
    --env "EXPECTED_UBUNTU_VERSION=$version" \
    --mount "type=bind,src=$output,dst=/artifacts" \
    --user root --entrypoint bash "$image" \
    -c 'trap '\''chown -R "$OUTPUT_UID:$OUTPUT_GID" /artifacts'\'' EXIT
        actual_version=$(. /etc/os-release; echo "$VERSION_ID")
        if [[ "$actual_version" != "$EXPECTED_UBUNTU_VERSION" ]]; then
            printf "Expected Ubuntu %s, got %s\n" "$EXPECTED_UBUNTU_VERSION" "$actual_version" >&2
            exit 1
        fi
        chown riscv:riscv /artifacts
        runuser -u riscv -- env HOME=/home/riscv riscv-act4-validate'
printf 'Saved ACT4 validation results to %s\n' "$output"
