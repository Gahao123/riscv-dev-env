#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
out=${ACT4_RESULTS:-/artifacts}
mkdir -p "$out"
out=$(cd -- "$out" && pwd)
export ACT4_WORKDIR=${ACT4_WORKDIR:-$out/work}
export ACT4_JOBS=${ACT4_JOBS:-2}
cd /act4
riscv-act4-probe 2>&1 | tee "$out/probe.log"
elf_dir="$ACT4_WORKDIR/spike-RVI20U64/elfs"
count=$(find "$elf_dir" -type f -name '*.elf' | wc -l)
expected=$(python3 -c 'import json; print(json.load(open("/usr/share/riscv-dev-env/act4.lock.json"))["act4"]["expected_tests"])')
test "$count" -eq "$expected"
grep -Fq "RESULT: All $expected tests passed." "$out/probe.log"
cp "$ACT4_WORKDIR/spike-RVI20U64/summary.log" "$out/summary.log"

# A simulator exit code of zero alone must not count as a passing ACT4 test.
negative=$(mktemp -d "$out/negative.XXXXXXXX")
mkdir "$negative/elfs"
find "$elf_dir" -type f -name 'I-add-00.elf' -exec cp '{}' "$negative/elfs/" \;
test -f "$negative/elfs/I-add-00.elf"
limited_command=$(python3 - <<'PY'
from pathlib import Path
command = Path('config/spike/spike-RVI20U64/run_cmd.txt').read_text().strip()
assert command.count('--instructions=100000000') == 1
print(command.replace('--instructions=100000000', '--instructions=1'))
PY
)
set +e
mise exec -- uv run --frozen --no-sync ./run_tests.py \
    --jobs 1 --timeout 5 "$limited_command" "$negative/elfs" 2>&1 | tee "$out/negative.log"
status=${PIPESTATUS[0]}
set -e
test "$status" -eq 1
grep -Fq 'exit code 0 but no RVCP-SUMMARY line found' "$out/negative.log"
test -z "$(git status --porcelain --untracked-files=no)"
ACT4_NEGATIVE_STATUS="$status" ACT4_TEST_COUNT="$count" ACT4_RESULTS="$out" \
mise exec -- uv run --frozen --no-sync python - <<'PY'
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import platform

out = Path(os.environ['ACT4_RESULTS'])
lock = json.loads(Path('/usr/share/riscv-dev-env/act4.lock.json').read_text())
versions = {
    name: subprocess.check_output(command, text=True).strip()
    for name, command in {
        'gcc': ['riscv64-unknown-elf-gcc', '-dumpfullversion'],
        'sail': ['sail_riscv_sim', '--version'],
        'mise': ['mise', '--version'],
        'ruby': ['ruby', '--version'],
        'bundler': ['bundle', '--version'],
        'uv': ['uv', '--version'],
    }.items()
}
versions['python'] = platform.python_version()
assert versions['python'] == lock['environment']['python']
assert versions['mise'].startswith(lock['mise']['version'] + ' ')
result = {
    'completed_at_utc': datetime.now(timezone.utc).isoformat(),
    'uid': os.getuid(),
    'ubuntu_version': platform.freedesktop_os_release()['VERSION_ID'],
    'host_architecture': platform.machine(),
    'act4_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'config': lock['act4']['config'],
    'extensions': lock['act4']['extensions'],
    'tests_passed': int(os.environ['ACT4_TEST_COUNT']),
    'negative_control_exit': int(os.environ['ACT4_NEGATIVE_STATUS']),
    'tracked_upstream_source_clean': True,
    'versions': versions,
}
(out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
PY
echo "ACT4 validation passed; results: $out/results.json"
