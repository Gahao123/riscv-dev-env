#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=24.04
if [[ "${1:-}" =~ ^(24\.04|26\.04)$ ]]; then version=$1; shift; fi
role=${1:-all}
[[ $# -le 1 && "$role" =~ ^(all|dev|ci|cert)$ ]] || { echo 'Usage: bash scripts/build-profiles.sh [24.04|26.04] [all|dev|ci|cert]' >&2; exit 2; }
seed=${ACT4_SEED_IMAGE:-riscv-act4:ubuntu-$version}
seed_id=$(docker image inspect --format '{{.Id}}' "$seed")
docker run --rm --network none --user root --entrypoint bash \
    --env "EXPECTED_UBUNTU_VERSION=$version" "$seed_id" -c \
    'test "$(. /etc/os-release; echo "$VERSION_ID")" = "$EXPECTED_UBUNTU_VERSION" && test -d /act4/.git && test -d /home/riscv/.cache/udb'
base=$(python3 - "$root/base-images.lock.json" "$version" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1]))['images'][sys.argv[2]])
PY
)
mkdir -p "$root/.cache"
context=$(mktemp -d "$root/.cache/profile-context.XXXXXXXX")
trap 'rm -rf -- "$context"' EXIT
mkdir -p "$context/tools"
cp "$root/Dockerfile.profiles" "$context/Dockerfile"
cp "$root/act4.lock.json" "$context/"
cp "$root/tools/"{prepare_profiles,seal_profiles}.py "$context/tools/"
cp -r "$root/profiles" "$context/"
roles=(ci cert dev)
if [[ "$role" != all ]]; then roles=("$role"); fi
for target in "${roles[@]}"; do
    args=(--platform linux/amd64 --build-arg "ACT4_SEED=$seed_id"
          --build-arg "RUNTIME_BASE=$base" --build-arg "UBUNTU_VERSION=$version" --target "$target"
          --tag "riscv-act4:ubuntu-$version-$target")
    for name in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
        if [[ -n "${!name:-}" ]]; then args+=(--build-arg "$name"); fi
    done
    if [[ -n "${ACT4_BUILD_NETWORK:-}" ]]; then args+=(--network "$ACT4_BUILD_NETWORK"); fi
    docker build "${args[@]}" "$context"
done
