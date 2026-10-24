#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Fetch and verify the archives pinned in act4.lock.json (Python 3.11+)."""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def fetch_sources():
    lock = json.loads((ROOT / 'act4.lock.json').read_text())
    cache = ROOT / '.cache' / 'act4'
    cache.mkdir(parents=True, exist_ok=True)
    for name in ('spike', 'softfloat', 'sail', 'mise'):
        source = lock[name]
        path = cache / f'{name}.tar.gz'

        def digest(file):
            with file.open('rb') as stream:
                return hashlib.file_digest(stream, 'sha256').hexdigest()

        if not path.exists() or digest(path) != source['sha256']:
            part = path.with_suffix('.part')
            request = urllib.request.Request(source['url'], headers={'User-Agent': 'riscv-dev-env'})
            with urllib.request.urlopen(request, timeout=120) as response, part.open('wb') as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            if digest(part) != source['sha256']:
                raise RuntimeError(f'{name}: SHA-256 mismatch; refusing archive')
            part.replace(path)
        print(f'Verified {name}: {source["sha256"]}', flush=True)


if __name__ == '__main__':
    fetch_sources()
