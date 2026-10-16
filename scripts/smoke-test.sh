#!/usr/bin/env bash
set -euo pipefail
tests=/usr/share/riscv-dev-env/tests
tmp=$(mktemp -d /tmp/riscv-smoke.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
compiler=riscv64-unknown-elf-gcc
test "$("$compiler" -dumpmachine)" = riscv64-unknown-elf
test "$("$compiler" -dumpfullversion)" = 16.2.0
"$compiler" --version | head -1
cat /opt/spike/share/source-version.txt
common=(-march=rv64imac_zicsr -mabi=lp64 -mcmodel=medany -msmall-data-limit=0 -O2
        -ffreestanding -nostdlib -nostartfiles -Wl,--no-relax -Wl,-T,"$tests/link.ld")
"$compiler" "${common[@]}" "$tests/start.S" "$tests/smoke.c" -o "$tmp/pass.elf"
riscv64-unknown-elf-readelf -h "$tmp/pass.elf"
timeout 20 spike --isa=RV64IMAC "$tmp/pass.elf"
riscv64-unknown-elf-g++ "${common[@]}" -std=c++20 -fno-exceptions -fno-rtti \
    "$tests/start.S" "$tests/smoke.cpp" -o "$tmp/pass-cxx.elf"
timeout 20 spike --isa=RV64IMAC "$tmp/pass-cxx.elf"
"$compiler" "${common[@]}" -DEXPECT_FAIL "$tests/start.S" "$tests/smoke.c" -o "$tmp/fail.elf"
set +e
timeout 20 spike --isa=RV64IMAC "$tmp/fail.elf" >"$tmp/expected-failure.log" 2>&1
status=$?
set -e
if [[ "$status" != 1 ]]; then
    cat "$tmp/expected-failure.log"
    printf 'Failure probe returned %s; expected 1\n' "$status" >&2
    exit 1
fi
printf 'PASS: C/C++ compilation, RISC-V execution and failure propagation\n'
