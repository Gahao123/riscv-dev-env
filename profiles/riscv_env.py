#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""ACT4 profile execution and detached artifact-manifest signatures."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
from datetime import datetime, timezone

SHARE = Path('/usr/share/riscv-dev-env')
ROOT = Path('/act4')


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def capture(command, **kwargs):
    return subprocess.check_output(command, text=True, **kwargs).strip()


def inventory(root, source=False):
    result = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if source and any(part in ('.git', '__pycache__') for part in relative.parts):
            continue
        if path.is_symlink():
            result[relative.as_posix()] = {'link': str(path.readlink())}
        elif path.is_file():
            result[relative.as_posix()] = {'sha256': sha(path)}
    return result


def verify_files(entries, root=None):
    for name, expected in entries.items():
        path = root / name if root else Path(name)
        if 'link' in expected:
            valid = path.is_symlink() and str(path.readlink()) == expected['link']
        else:
            valid = path.is_file() and not path.is_symlink() and sha(path) == expected['sha256']
        if not valid:
            raise ValueError(f'Input verification failed: {name}')


def prepare(source=None):
    if source:
        source = Path(source).resolve()
        if source == ROOT or ROOT in source.parents or not (source / '.git').is_dir():
            raise ValueError('--source requires a separate standalone Git checkout (.git directory)')
        for child in ROOT.iterdir():
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child)
            else:
                child.unlink()
        shutil.copytree(source, ROOT, dirs_exist_ok=True, symlinks=True,
                        ignore=shutil.ignore_patterns('.venv', 'work', 'work-*', '__pycache__'))
    elif not (ROOT / 'Makefile').exists():
        with tarfile.open(SHARE / 'act4-source.tar.gz') as archive:
            archive.extractall(ROOT, filter='data')
    baseline = json.loads((SHARE / 'source-manifest.json').read_text())
    dependency_names = [name for name in baseline if name.endswith('pyproject.toml')]
    dependency_names += ['uv.lock', '.python-version', '.mise.toml',
                         'framework/src/act/data/Gemfile', 'framework/src/act/data/Gemfile.lock']
    for name in dependency_names:
        if not (ROOT / name).is_file() or sha(ROOT / name) != baseline[name]['sha256']:
            raise ValueError(f'Dependency metadata changed: {name}; rebuild the seed and profile images')


def logged(command, path, env=None):
    with path.open('w') as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in process.stdout:
            print(line, end='', flush=True)
            log.write(line)
        status = process.wait()
    return status


def verify_bundle(directory, public_key):
    directory = Path(directory).resolve()
    subprocess.run(['openssl', 'pkeyutl', '-verify', '-pubin', '-inkey', public_key,
                    '-rawin', '-in', str(directory / 'manifest.json'),
                    '-sigfile', str(directory / 'manifest.sig')], check=True)
    manifest = json.loads((directory / 'manifest.json').read_text())
    entries = manifest['files']
    for name in entries:
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or not (directory / path).resolve().is_relative_to(directory):
            raise ValueError(f'Unsafe manifest path: {name}')
    verify_files(entries, directory)
    actual = inventory(directory)
    for metadata in ('manifest.json', 'manifest.sig'):
        actual.pop(metadata, None)
    if actual != entries:
        raise ValueError('Bundle has missing, changed or additional artifacts')
    print('Signature and all artifact hashes verified.', flush=True)


def run(args):
    profile = Path('/etc/riscv-act4-profile').read_text().strip()
    lock = json.loads((SHARE / 'act4.lock.json').read_text())
    out = Path(args.output).resolve()
    if out == ROOT or ROOT in out.parents or out in ROOT.parents:
        raise ValueError('Output must be separate from /act4')
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        raise ValueError('Output directory must be empty; choose a fresh directory')
    if args.jobs < 1 or args.timeout < 1:
        raise ValueError('Jobs and timeout must be positive')
    if profile == 'cert':
        if args.source or not args.signing_key or not args.verification_key:
            raise ValueError('cert requires external signing/verification keys and refuses --source')
        verify_files(json.loads((SHARE / 'runtime-manifest.json').read_text()))
    prepare(args.source)
    baseline = json.loads((SHARE / 'source-manifest.json').read_text())
    revision = capture(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'])
    dirty = capture(['git', '-C', str(ROOT), 'status', '--porcelain', '--untracked-files=no'])
    if profile == 'cert' and (revision != lock['act4']['commit'] or inventory(ROOT, source=True) != baseline):
        raise ValueError('cert source differs from the sealed checkout')
    if capture(['riscv64-unknown-elf-gcc', '-dumpfullversion']) != '16.2.0':
        raise ValueError('Unexpected compiler version')
    if capture(['sail_riscv_sim', '--version']) != lock['sail']['version']:
        raise ValueError('Unexpected Sail version')
    config = lock['act4']['config']
    work = out / 'work'
    env = os.environ.copy()
    env.update(EXTENSIONS=lock['act4']['extensions'], FAST='True',
               CONFIG_FILES=config, WORKDIR=str(work))
    status = logged(['make', f'-j{args.jobs}'], out / 'build.log', env)
    if status:
        return status
    name = Path(config).parent.name
    elf_dir = work / name / 'elfs'
    elfs = sorted(elf_dir.rglob('*.elf'))
    if not elfs:
        raise ValueError('ACT4 produced no test ELFs')
    command = (ROOT / Path(config).parent / 'run_cmd.txt').read_text().strip()
    status = logged([sys.executable, 'run_tests.py', '--jobs', str(args.jobs),
                     '--timeout', str(args.timeout), command, str(elf_dir)], out / 'run.log')
    if status:
        return status
    summary = work / name / 'summary.log'
    if summary.read_text().count('RVCP-SUMMARY: TEST PASSED') != len(elfs):
        raise ValueError('Per-test success count does not match ELF count')
    shutil.copy2(summary, out / 'summary.log')
    negative_dir = out / 'negative' / 'elfs'
    negative_dir.mkdir(parents=True)
    shutil.copy2(elfs[0], negative_dir / elfs[0].name)
    limited, count = re.subn(r'--instructions=\d+', '--instructions=1', command)
    if count != 1:
        raise ValueError('Expected one Spike instruction-budget option for the negative control')
    negative = logged([sys.executable, 'run_tests.py', '--jobs', '1', '--timeout', '5',
                       limited, str(negative_dir)], out / 'negative.log')
    if negative != 1 or 'exit code 0 but no RVCP-SUMMARY line found' not in (out / 'negative.log').read_text():
        raise ValueError('Early-stop control was not rejected as expected')
    if profile == 'cert' and inventory(ROOT, source=True) != baseline:
        raise ValueError('cert source changed during generation/build')
    result = {
        'completed_at_utc': datetime.now(timezone.utc).isoformat(), 'profile': profile,
        'ubuntu_version': platform.freedesktop_os_release()['VERSION_ID'], 'uid': os.getuid(),
        'act4_revision': revision, 'source_supplied': bool(args.source),
        'source_dirty_before_build': bool(dirty), 'selected_extensions': lock['act4']['extensions'],
        'tests_passed': len(elfs), 'negative_control_exit': negative,
        'gcc': capture(['riscv64-unknown-elf-gcc', '-dumpfullversion']),
        'sail': capture(['sail_riscv_sim', '--version']), 'python': platform.python_version(),
        'ruby': capture(['ruby', '--version']), 'bundler': capture(['bundle', '--version']),
        'sealed_inputs_verified': profile == 'cert',
        'runtime_manifest_sha256': sha(SHARE / 'runtime-manifest.json'),
        'act4_lock_sha256': sha(SHARE / 'act4.lock.json'),
        'scope': 'RV64 I integration probe on Spike; no official certification claim',
    }
    (out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    if profile == 'cert':
        subprocess.run(['openssl', 'pkey', '-in', args.signing_key, '-pubout',
                        '-out', str(out / 'signer-public-key.pem')], check=True)
        manifest = {'format': 'riscv-dev-env-artifacts-v1', 'profile': profile,
                    'act4_revision': revision, 'files': inventory(out)}
        (out / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
        subprocess.run(['openssl', 'pkeyutl', '-sign', '-inkey', args.signing_key, '-rawin',
                        '-in', str(out / 'manifest.json'), '-out', str(out / 'manifest.sig')], check=True)
        verify_bundle(out, args.verification_key)
    print(f'ACT4 {profile} verification passed: {len(elfs)} tests; results: {out}', flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('prepare')
    runner = sub.add_parser('run')
    runner.add_argument('--source', help='dev/CI: a mounted standalone ACT4 Git checkout')
    runner.add_argument('--output', default='/artifacts')
    runner.add_argument('--jobs', type=int, default=2)
    runner.add_argument('--timeout', type=int, default=30)
    runner.add_argument('--signing-key')
    runner.add_argument('--verification-key')
    verifier = sub.add_parser('verify')
    verifier.add_argument('directory')
    verifier.add_argument('--public-key', required=True, help='externally trusted public key')
    args = parser.parse_args()
    try:
        if args.command == 'prepare':
            prepare()
            return 0
        if args.command == 'verify':
            verify_bundle(args.directory, args.public_key)
            return 0
        return run(args)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
