# Ubuntu 24.04 dev / CI / cert prototypes

These three container roles extend the pinned ACT4 environment. They retain the
RV64 I integration scope: generate tests, compute Sail reference signatures,
compile self-checking ELFs, run them on Spike, and reject an early-stop control.
They are the first container matrix for DevPartners #47. Ubuntu 26.04 variants,
VM images, broader ISA coverage, and ACT-approved certification/signing policy
remain subsequent work.

| Role | Default behavior | Source policy | Additional purpose |
|---|---|---|---|
| `dev` | Interactive Bash | Packaged checkout or developer-supplied checkout | Native build tools, editor, GDB multiarch, VS Code configuration |
| `ci` | Noninteractive verification | Packaged checkout or mounted standalone Git checkout | Test changed source, record the actual revision, propagate failures |
| `cert` | Fixed-input verification and signing | Sealed packaged checkout only | Verify runtime/source hashes, run with read-only root, sign artifacts with an external key |

## Build the roles

Prerequisites: the validated `riscv-act4:ubuntu-24.04` integration image, Docker,
and Python 3.11+ on linux/amd64. The integration image supplies installed tools;
GCC and Spike are not rebuilt by the profile recipe.

```bash
bash scripts/build-profiles.sh all
# Or build a target separately:
bash scripts/build-profiles.sh ci
```

This creates `riscv-act4:ubuntu-24.04-dev`, `riscv-act4:ubuntu-24.04-ci`, and
`riscv-act4:ubuntu-24.04-cert`. `ACT4_SEED_IMAGE` selects another compatible
Ubuntu 24.04 integration seed. The build resolves the seed to its local image ID.
The runtime Ubuntu manifest is pinned in `base-images.lock.json`.

The multistage recipe copies installed GCC, Sail, Ruby, Python and the virtual
environment into a fresh Ubuntu runtime. It strips host Spike debug sections,
excludes the old Phase 1 Spike, tool-manager binaries and download caches, and
removes generated Ruby API documentation and gem archives. UDB's native
Z3/eqntott/espresso/must libraries and programs remain under `/opt/act4-cache`:
they are runtime dependencies, even though the seed stored them in a cache.
Installed upstream notices and the ACT4 source checkout remain in the image.

The ACT4 source is stored as an archive and materialized into `/act4` at runtime.
The relocated Python environment is `/opt/act4-venv`; `VIRTUAL_ENV` and `PATH`
select ACT4's supported direct-CLI Make path. mise and uv are not needed at runtime.

Network/proxy setup follows `ACT4.md`. `ACT4_BUILD_NETWORK=host` is optional for
Linux hosts whose existing proxy is on host loopback. This recipe still uses
live Ubuntu package repositories; byte-identical rebuilds are not claimed.

## Verify CI and dev

```bash
bash scripts/check-profile.sh ci
bash scripts/check-profile.sh dev
```

Each call uses a fresh container, no network, two CPU equivalents, 4 GiB RAM and
6 GiB including swap. Tests run as UID 1001. `ACT4_OUTPUT=/absolute/empty/path`
selects a new artifact directory; existing contents are rejected. The image
inspection record is saved alongside that directory as `<path>.image.json`.

To test a different ACT4 revision or uncommitted code changes:

```bash
ACT4_SOURCE=/absolute/path/to/act4-checkout \
  ACT4_OUTPUT=/absolute/empty/ci-output bash scripts/check-profile.sh ci
```

The source mount is read-only. The runner copies the checkout to its writable
workspace, generates/compiles/runs from that copy, and records its actual commit
and initial dirty state. A standalone `.git` directory is required; a worktree's
external `.git` pointer is not supported yet. Dependency metadata (`uv.lock`,
Gemfile/lock, `.mise.toml`, `.python-version`, workspace `pyproject.toml` files)
must match the prepared environment. Rebuild the seed and role images when these
dependencies change. The test count can change with source changes; the baseline
validation record establishes the current 51-test selection.

## Develop and inspect RISC-V ELFs

```bash
docker run --rm -it \
  --mount type=volume,src=act4-dev-source,dst=/act4 \
  riscv-act4:ubuntu-24.04-dev
# Inside the container:
git switch -c my-work
gdb-multiarch --version
```

The named volume retains source edits. In the shell, `make` and the ACT4 Python
CLIs use the already installed dependencies. The image also contains the native
C/C++ build tools and `vim`. Use `gdb-multiarch` to load/disassemble generated
RISC-V ELFs; live Spike remote-debug transport is not configured by this prototype.

`.devcontainer/devcontainer.json` provides a VS Code Dev Containers entry point.
It mounts this infrastructure repository at `/workspace`, prepares ACT4 under
`/act4`, and selects the supplied Python interpreter. The configured UID is 1001;
host bind-mount permissions must permit that user to write. IDE configuration
is supplied separately from CLI/GDB validation; a GUI session is not part of the
automated acceptance record.

## Cert: fixed inputs and project-specific signatures

The cert role verifies the sealed tool-prefix file inventory and source tree,
rejects alternative source checkouts, and uses the pinned config and suite. The
host wrapper supplies a read-only root filesystem and writable tmpfs work/cache
directories. Results persist only in the artifact mount.

Generate a **local demonstration identity**, or supply your own approved signing
identity. Never add private keys to Git or an image:

```bash
mkdir -p .cache/demo-keys
umask 077
openssl genpkey -algorithm ED25519 -out .cache/demo-keys/private.pem
openssl pkey -in .cache/demo-keys/private.pem -pubout -out .cache/demo-keys/public.pem
chmod 644 .cache/demo-keys/public.pem

ACT4_SIGNING_KEY="$PWD/.cache/demo-keys/private.pem" \
ACT4_VERIFICATION_KEY="$PWD/.cache/demo-keys/public.pem" \
ACT4_OUTPUT=/absolute/empty/cert-output bash scripts/check-profile.sh cert
```

The private key is mounted read-only for setup and copied to tmpfs with restricted
permissions for the testing user. It is not copied into the image or artifacts.
Successful verification produces `results.json`, logs, ELFs, `manifest.json`,
`manifest.sig`, and the public signer key. The manifest records SHA-256 for every
artifact and has a detached OpenSSL signature.

Verify against an **externally trusted** public key:

```bash
docker run --rm --network none \
  --mount type=bind,src=/absolute/cert-output,dst=/bundle,readonly \
  --mount type=bind,src=/absolute/trusted-public.pem,dst=/trusted.pem,readonly \
  riscv-act4:ubuntu-24.04-cert \
  riscv-act4-verify /bundle --public-key /trusted.pem
```

The public key delivered in the bundle identifies its signer; it does not itself
establish trust. Changing an artifact, changing the manifest, adding an unlisted
file, using the wrong trusted key, or introducing an unsafe manifest path fails
verification. A profile-image override can be pinned with `ACT4_PROFILE_IMAGE`;
the wrapper still checks the requested role and actual Ubuntu version.

These signatures demonstrate this project's artifact-integrity workflow. They
are not an official ACT certificate, approved test-suite release, or an assertion
that all RVI20U64 extensions passed. Host administrators and image publishers
remain outside the in-container file-hash check's trust boundary.

## Evidence, provenance and checks

- Source/version pins: `act4.lock.json` and the inherited toolchain source lock.
- Runtime package inventory: `/usr/share/riscv-dev-env/runtime-packages.txt`;
  development additions: `dev-packages.txt`.
- Sealed runtime and source inventories: `runtime-manifest.json` and
  `source-manifest.json` in the same directory. They describe this exact built
  image; the image ID should be retained with verification results.
- Signature regressions: `python3 tests/test_profiles.py` (requires OpenSSL).
- Integration results: the role-specific validation record under `validation/`.

The source is the already pinned ACT4 checkout; no upstream test or generator
patches are introduced by this matrix. Direct virtual-environment execution
follows ACT4's Makefile fallback. Upstream components retain their own licenses.
Codex assisted with the role recipes, runner, verification tests and local runs.
