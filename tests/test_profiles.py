# SPDX-License-Identifier: MIT
"""Real OpenSSL signature and artifact-boundary regressions; no network needed."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('riscv_env', Path(__file__).resolve().parents[1] / 'profiles/riscv_env.py')
env = importlib.util.module_from_spec(spec)
spec.loader.exec_module(env)


class ArtifactSignatures(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle = self.root / 'bundle'
        self.bundle.mkdir()
        self.private = self.root / 'private.pem'
        self.public = self.root / 'public.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(self.private)], check=True)
        subprocess.run(['openssl', 'pkey', '-in', str(self.private), '-pubout', '-out', str(self.public)], check=True)
        (self.bundle / 'payload.txt').write_text('verified test artifact\n')
        self.manifest = {'files': env.inventory(self.bundle)}
        self.sign()

    def sign(self):
        (self.bundle / 'manifest.json').write_text(json.dumps(self.manifest))
        subprocess.run(['openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(self.private),
                        '-in', str(self.bundle / 'manifest.json'), '-out', str(self.bundle / 'manifest.sig')], check=True)

    def test_valid_signature_and_content(self):
        env.verify_bundle(self.bundle, str(self.public))

    def test_changed_payload_rejected(self):
        (self.bundle / 'payload.txt').write_text('tampered\n')
        with self.assertRaises(ValueError):
            env.verify_bundle(self.bundle, str(self.public))

    def test_added_hidden_payload_rejected(self):
        (self.bundle / '.git').mkdir()
        (self.bundle / '.git' / 'unexpected').write_text('extra\n')
        with self.assertRaises(ValueError):
            env.verify_bundle(self.bundle, str(self.public))

    def test_changed_manifest_rejected(self):
        with (self.bundle / 'manifest.json').open('a') as stream:
            stream.write(' ')
        with self.assertRaises(subprocess.CalledProcessError):
            env.verify_bundle(self.bundle, str(self.public))

    def test_wrong_trusted_key_rejected(self):
        wrong_private = self.root / 'wrong-private.pem'
        wrong_public = self.root / 'wrong-public.pem'
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(wrong_private)], check=True)
        subprocess.run(['openssl', 'pkey', '-in', str(wrong_private), '-pubout', '-out', str(wrong_public)], check=True)
        with self.assertRaises(subprocess.CalledProcessError):
            env.verify_bundle(self.bundle, str(wrong_public))

    def test_signed_parent_path_rejected(self):
        self.manifest['files']['../outside'] = {'sha256': '0' * 64}
        self.sign()
        with self.assertRaises(ValueError):
            env.verify_bundle(self.bundle, str(self.public))


if __name__ == '__main__':
    unittest.main()
