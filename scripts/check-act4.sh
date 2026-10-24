#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image=${ACT4_IMAGE:-riscv-act4:ubuntu-24.04}
output=${ACT4_OUTPUT:-$root/logs/act4-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$output"
output=$(cd -- "$output" && pwd)
docker image inspect "$image" > "$output/image-inspect.json"
# The image's default user owns a new output tree. No dependency downloads are allowed.
docker run --rm --network none --cpus 2 --memory 4g --memory-swap 6g --pids-limit 512 \
    --env "ACT4_JOBS=${ACT4_JOBS:-2}" \
    --env "OUTPUT_UID=$(id -u)" --env "OUTPUT_GID=$(id -g)" \
    --mount "type=bind,src=$output,dst=/artifacts" \
    --user root --entrypoint bash "$image" \
    -c 'trap '\''chown -R "$OUTPUT_UID:$OUTPUT_GID" /artifacts'\'' EXIT
        chown riscv:riscv /artifacts
        runuser -u riscv -- env HOME=/home/riscv riscv-act4-validate'
printf 'Saved ACT4 validation results to %s\n' "$output"
