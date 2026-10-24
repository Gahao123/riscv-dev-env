#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Install the checked ACT4 system tools inside the Docker build."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

LOCK = Path('/usr/share/riscv-dev-env/act4.lock.json')


def main():
    lock = json.loads(LOCK.read_text())
    jobs = os.environ.get('BUILD_JOBS', '2')
    if not jobs.isdecimal() or int(jobs) < 1:
        raise ValueError('BUILD_JOBS must be a positive integer')
    with tempfile.TemporaryDirectory(prefix='act4-install-') as temporary:
        root = Path(temporary)
        sources = {}
        for name in ('spike', 'softfloat', 'sail', 'mise'):
            archive = Path('/tmp/act4-archives') / f'{name}.tar.gz'
            with archive.open('rb') as stream:
                actual = hashlib.file_digest(stream, 'sha256').hexdigest()
            if actual != lock[name]['sha256']:
                raise RuntimeError(f'{name}: SHA-256 mismatch')
            target = root / name
            target.mkdir()
            with tarfile.open(archive) as source:
                source.extractall(target, filter='data')
            entries = list(target.iterdir())
            if len(entries) != 1 or not entries[0].is_dir():
                raise RuntimeError(f'{name}: expected one archive root directory')
            sources[name] = entries[0]

        spike = sources['spike']
        shutil.copytree(sources['softfloat'], spike / 'berkeley-softfloat-3', dirs_exist_ok=True)
        build = root / 'build'
        build.mkdir()
        prefix = lock['spike']['install_prefix']
        subprocess.run([str(spike / 'configure'), f'--prefix={prefix}'], cwd=build, check=True)
        subprocess.run(['make', f'-j{jobs}'], cwd=build, check=True)
        subprocess.run(['make', 'install'], cwd=build, check=True)
        share = Path(prefix) / 'share'
        share.mkdir(exist_ok=True)
        (share / 'source-revision.txt').write_text(lock['spike']['commit'] + '\n')
        licenses = share / 'source-licenses'
        licenses.mkdir(exist_ok=True)
        shutil.copy2(spike / 'LICENSE', licenses / 'spike-LICENSE')
        shutil.copy2(sources['softfloat'] / 'COPYING.txt', licenses / 'softfloat-COPYING.txt')
        shutil.copytree(sources['sail'], lock['sail']['install_prefix'], dirs_exist_ok=True)
        subprocess.run(['install', '-D', '-m', '755', str(sources['mise'] / 'bin/mise'),
                        '/home/riscv/.local/bin/mise'], check=True)
    # Temporary source and object files are removed before this Docker layer ends.


if __name__ == '__main__':
    main()
