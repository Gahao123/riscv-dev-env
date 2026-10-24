#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd /act4
mapfile -t settings < <(python3 - <<'PY'
import json
from pathlib import Path
import tomllib

lock = json.loads(Path('/usr/share/riscv-dev-env/act4.lock.json').read_text())
tools = tomllib.loads(Path('.mise.toml').read_text())['tools']
for tool in ('ruby', 'uv', 'bundler'):
    key = 'gem:bundler' if tool == 'bundler' else tool
    assert tools[key] == lock['environment'][tool], f'Unexpected upstream {tool} version'
print(lock['environment']['python'])
PY
)
test "${#settings[@]}" -eq 1
export UV_PYTHON="${settings[0]}"
export BUNDLE_JOBS="${BUILD_JOBS:-2}"
export MISE_JOBS="${BUILD_JOBS:-2}"
mise trust /act4/.mise.toml
mise install
mise exec -- uv python install "$UV_PYTHON"
mise exec -- uv sync --frozen --python "$UV_PYTHON"
mise exec -- bundle install --gemfile framework/src/act/data/Gemfile --jobs "$BUNDLE_JOBS"
mise exec -- uv run --frozen --no-sync act --help
test -z "$(git status --porcelain --untracked-files=no)"
