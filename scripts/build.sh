#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:-24.04}
base=$(python3 - "$root/base-images.lock.json" "$version" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['images'][sys.argv[2]])
PY
)
python3 "$root/tools/fetch_sources.py"
docker build --platform linux/amd64 --build-arg "BASE_IMAGE=$base" \
    --build-arg "UBUNTU_VERSION=$version" --build-arg "BUILD_JOBS=${BUILD_JOBS:-2}" \
    --tag "riscv-dev:ubuntu-$version" "$root"
docker run --rm "riscv-dev:ubuntu-$version" riscv-smoke-test
