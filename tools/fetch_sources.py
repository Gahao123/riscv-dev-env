#!/usr/bin/env python3
"""Download locked source archives; --record-hashes is an explicit maintainer update."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--record-hashes', action='store_true')
args = parser.parse_args()
lock_file = ROOT / 'sources.lock.json'
lock = json.loads(lock_file.read_text(encoding='utf-8'))
cache = ROOT / '.cache'
cache.mkdir(exist_ok=True)

def download(source):
    path = cache / source['file']
    algorithm = 'sha512' if 'sha512' in source else 'sha256'
    expected = source.get(algorithm)
    if expected is None and not args.record_hashes:
        raise RuntimeError(f"{source['name']}: checksum missing; review and record the source lock first")
    def digest():
        with path.open('rb') as stream:
            return hashlib.file_digest(stream, algorithm).hexdigest()
    if not path.exists() or (expected is not None and digest() != expected):
        part = path.with_suffix(path.suffix + '.part')
        request = urllib.request.Request(source['url'], headers={'User-Agent': 'RISC-V-Dev-Environment-Prototype'})
        with urllib.request.urlopen(request, timeout=120) as response, part.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        part.replace(path)
    actual = digest()
    if expected is not None and actual != expected:
        raise RuntimeError(f"{source['name']}: checksum mismatch")
    source[algorithm] = actual
    print(f"Verified {source['file']} ({path.stat().st_size} bytes)", flush=True)
    return source

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    lock['sources'] = list(pool.map(download, lock['sources']))
if args.record_hashes:
    lock_file.write_text(json.dumps(lock, indent=2) + '\n', encoding='utf-8')
