#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:-24.04}
if [[ $# -gt 1 || ! "$version" =~ ^(24\.04|26\.04)$ ]]; then
    echo 'Usage: bash scripts/build-act4.sh [24.04|26.04]' >&2
    exit 2
fi
base=${PHASE1_IMAGE:-riscv-dev:ubuntu-$version}
image=${ACT4_IMAGE:-riscv-act4:ubuntu-$version}
jobs=${BUILD_JOBS:-2}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo 'BUILD_JOBS must be a positive integer' >&2; exit 2; }
docker image inspect "$base" >/dev/null || {
    printf 'Build the Phase 1 Ubuntu %s image first: bash scripts/build.sh %s\n' "$version" "$version" >&2
    exit 1
}
# Use its immutable local ID during the build, even if a tag is changed elsewhere.
base_id=$(docker image inspect --format '{{.Id}}' "$base")
python3 "$root/tools/fetch_act4_sources.py"
context=$(mktemp -d "$root/.cache/act4/context.XXXXXXXX")
trap 'rm -rf -- "$context"' EXIT
mkdir -p "$context/archives" "$context/tools" "$context/scripts"
cp "$root/Dockerfile.act4" "$context/Dockerfile"
cp "$root/act4.lock.json" "$context/"
cp "$root/tools/install_act4_system.py" "$context/tools/"
cp "$root/scripts/"{install-act4-user,run-act4-probe,validate-act4}.sh "$context/scripts/"
cp "$root/.cache/act4/"{spike,softfloat,sail,mise}.tar.gz "$context/archives/"
args=(--platform linux/amd64 --build-arg "PHASE1_IMAGE=$base_id"
      --build-arg "UBUNTU_VERSION=$version" --build-arg "BUILD_JOBS=$jobs" --tag "$image")
# Docker's predefined proxy build arguments are not declared/persisted by this recipe.
for name in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
    if [[ -n "${!name:-}" ]]; then args+=(--build-arg "$name"); fi
done
if [[ -n "${ACT4_BUILD_NETWORK:-}" ]]; then args+=(--network "$ACT4_BUILD_NETWORK"); fi
docker build "${args[@]}" "$context"
printf 'Built %s from %s\nValidate offline: bash scripts/check-act4.sh %s\n' "$image" "$base_id" "$version"
