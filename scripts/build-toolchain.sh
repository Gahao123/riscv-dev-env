#!/usr/bin/env bash
set -euo pipefail
jobs=${BUILD_JOBS:-2}
mkdir -p /build/{toolchain,gcc,binutils,newlib} /opt/riscv
python3 - <<'PY'
import hashlib, json
from pathlib import Path
lock = json.loads(Path('/recipe/sources.lock.json').read_text())
for source in lock['sources']:
    path = Path('/archives') / source['file']
    algorithm = 'sha512' if 'sha512' in source else 'sha256'
    with path.open('rb') as stream:
        assert hashlib.file_digest(stream, algorithm).hexdigest() == source[algorithm], source['name']
PY
tar -xf /archives/toolchain-2026.08.27.tar.gz --strip-components=1 -C /build/toolchain
tar -xf /archives/gcc-16.2.0.tar.xz --strip-components=1 -C /build/gcc
tar -xf /archives/binutils-6ce87bbc.tar.gz --strip-components=1 -C /build/binutils
tar -xf /archives/newlib-8ba4275b.tar.gz --strip-components=1 -C /build/newlib
cd /build/toolchain
./configure --prefix=/opt/riscv --with-arch=rv64gc --with-abi=lp64d \
    --disable-multilib --disable-gdb --disable-linux \
    --with-gcc-src=/build/gcc --with-binutils-src=/build/binutils \
    --with-newlib-src=/build/newlib
make -j"$jobs"
test "$(/opt/riscv/bin/riscv64-unknown-elf-gcc -dumpfullversion)" = '16.2.0'
mkdir -p /opt/riscv/share/source-licenses
cp /build/gcc/COPYING* /opt/riscv/share/source-licenses/
cp /recipe/sources.lock.json /opt/riscv/share/source-licenses/
