#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

act4_root=${ACT4_ROOT:-/act4}
lock=${ACT4_LOCK:-/usr/share/riscv-dev-env/act4.lock.json}
workdir=${ACT4_WORKDIR:-/act4/work}
jobs=${ACT4_JOBS:-2}
timeout_seconds=${ACT4_TEST_TIMEOUT:-30}

for value in "$jobs" "$timeout_seconds"; do
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        printf 'Job count and timeout must be positive integers\n' >&2
        exit 2
    fi
done

export PATH="$HOME/.local/bin:/opt/spike-act4/bin:/opt/sail/bin:$PATH"
export UV_LINK_MODE=copy
cd -- "$act4_root"
command -v mise >/dev/null
test -x /opt/spike-act4/bin/spike
test -x /opt/sail/bin/sail_riscv_sim
test -f "$lock"

# Use the workspace's pinned Python environment to read this project's lock.
mapfile -t settings < <(mise exec -- uv run --frozen --no-sync python - "$lock" <<'PY'
import json
import sys
from pathlib import Path

lock = json.loads(Path(sys.argv[1]).read_text())
print(lock['act4']['commit'])
print(lock['act4']['config'])
print(lock['act4']['extensions'])
print(lock['spike']['commit'])
PY
)
test "${#settings[@]}" -eq 4
expected_commit=${settings[0]}
config=${settings[1]}
extensions=${settings[2]}
test "$(cat /opt/spike-act4/share/source-revision.txt)" = "${settings[3]}"
test "$(git rev-parse HEAD)" = "$expected_commit"
test "$(riscv64-unknown-elf-gcc -dumpfullversion)" = 16.2.0
test "$(/opt/sail/bin/sail_riscv_sim --version)" = 0.16

EXTENSIONS="$extensions" FAST=True CONFIG_FILES="$config" WORKDIR="$workdir" make -j"$jobs"

config_dir=$(dirname -- "$config")
config_name=$(basename -- "$config_dir")
elf_dir="$workdir/$config_name/elfs"
if [[ ! -d "$elf_dir" ]] || ! find "$elf_dir" -type f -name '*.elf' -print -quit | grep -q .; then
    printf 'ACT4 produced no test ELFs: %s\n' "$elf_dir" >&2
    exit 1
fi
run_command=$(cat -- "$config_dir/run_cmd.txt")
mise exec -- uv run --frozen --no-sync ./run_tests.py \
    --jobs "$jobs" --timeout "$timeout_seconds" "$run_command" "$elf_dir"
