#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Export installed tools from the validated image, without rebuilding GCC/Spike."""
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

DEST = Path('/export/rootfs')
RUBY = Path('/home/riscv/.local/share/mise/installs/ruby/3.4.11')


def copy(source, target=None):
    source = Path(source)
    target = DEST / str(target or source).lstrip('/')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, target, symlinks=True)
    return target


def main():
    DEST.mkdir(parents=True)
    copy('/opt/riscv')
    spike = copy('/opt/spike-act4')
    for path in spike.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                magic = stream.read(8)
            if magic.startswith(b'\x7fELF') or magic == b'!<arch>\n':
                subprocess.run(['strip', '--strip-debug', str(path)], check=True)
    copy('/opt/sail')
    ruby = copy(RUBY)
    shutil.rmtree(ruby / 'share/ri', ignore_errors=True)
    shutil.rmtree(ruby / 'lib/ruby/gems/3.4.0/cache', ignore_errors=True)
    copy('/home/riscv/.local/share/uv/python')
    venv = copy('/act4/.venv', '/opt/act4-venv')
    for path in (venv / 'bin').iterdir():
        if path.is_file() and not path.is_symlink():
            data = path.read_bytes()
            if data.startswith(b'#!'):
                path.write_bytes(data.replace(b'/act4/.venv', b'/opt/act4-venv'))
    share = DEST / 'usr/share/riscv-dev-env'
    share.mkdir(parents=True)
    for name in ('sources.lock.json',):
        shutil.copy2(Path('/usr/share/riscv-dev-env') / name, share / name)
    revision = subprocess.check_output(['git', '-c', 'safe.directory=/act4', '-C', '/act4',
                                        'rev-parse', 'HEAD'], text=True).strip()
    (share / 'act4-source-revision.txt').write_text(revision + '\n')
    with tarfile.open(share / 'act4-source.tar.gz', 'w:gz') as archive:
        for path in sorted(Path('/act4').iterdir()):
            if path.name in ('.venv', 'work', 'work-offline', '__pycache__'):
                continue
            archive.add(path, arcname=path.name, filter=lambda entry: None if '__pycache__' in Path(entry.name).parts else entry)
    (share / 'export-policy.json').write_text(json.dumps({
        'gcc': 'copied unchanged', 'spike': 'host debug sections removed; licenses retained',
        'excluded': ['Phase 1 Spike v1.1.0', 'mise/uv/prek/shellcheck binaries',
                     'download caches', 'Ruby generated API documentation', 'Ruby gem archives'],
        'source_revision': revision,
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
