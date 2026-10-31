#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Record the runtime inventory and the pristine ACT4 source inventory."""
import hashlib
import json
from pathlib import Path
import tarfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    share = Path('/usr/share/riscv-dev-env')
    source = {}
    with tarfile.open(share / 'act4-source.tar.gz') as archive:
        for entry in archive:
            if '.git' in Path(entry.name).parts:
                continue
            if entry.issym():
                source[entry.name] = {'link': entry.linkname}
            elif entry.isfile() or entry.islnk():
                source[entry.name] = {'sha256': hashlib.file_digest(archive.extractfile(entry), 'sha256').hexdigest()}
    (share / 'source-manifest.json').write_text(json.dumps(source, sort_keys=True) + '\n')
    files = {}
    roots = ['/opt/riscv', '/opt/spike-act4', '/opt/sail', '/opt/act4-venv', '/opt/act4-cache',
             '/home/riscv/.local', '/usr/local/lib/riscv_env.py',
             '/usr/share/riscv-dev-env/act4.lock.json',
             '/usr/share/riscv-dev-env/act4-source.tar.gz',
             '/usr/share/riscv-dev-env/source-manifest.json',
             '/usr/share/riscv-dev-env/act4-source-revision.txt',
             '/usr/share/riscv-dev-env/runtime-packages.txt',
             '/usr/local/bin/riscv-act4-entry', '/usr/local/bin/riscv-act4-run',
             '/usr/local/bin/riscv-act4-verify']
    for root in roots:
        root = Path(root)
        for path in sorted(root.rglob('*')) if root.is_dir() else [root]:
            if path.is_symlink():
                files[str(path)] = {'link': str(path.readlink())}
            elif path.is_file():
                files[str(path)] = {'sha256': digest(path)}
    (share / 'runtime-manifest.json').write_text(json.dumps(files, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
