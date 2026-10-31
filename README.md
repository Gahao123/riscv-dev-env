# RISC-V development and ACT4 environments

Build and validate RISC-V development, CI, and fixed-input test containers on
**Ubuntu 24.04 LTS and 26.04 LTS**, for an x86_64 Linux/WSL2 host.
This project implements container prototypes for
[RISC-V DevPartners #47](https://github.com/riscv-admin/dev-partners/issues/47),
with guidance from Wei Wu. Build recipes, source/version locks, and validation
records are published here; container images are currently built locally.

## Current deliverables

Phase 1 supplies GCC 16.2.0/Newlib and Spike. Phase 2 integrates a pinned ACT4
checkout and supplies six role images. The container prototypes are ready for
review; formal acceptance and the remaining VM/certification scope need agreement
with the ACT team.

| Role | Purpose | Ubuntu 24.04 | Ubuntu 26.04 |
|---|---|---|---|
| `dev` | Interactive development, native build tools, GDB multiarch, IDE configuration | 5.48 GB | 5.63 GB |
| `ci` | Offline automated checks of packaged or mounted ACT4 source | 5.05 GB | 5.11 GB |
| `cert` | Sealed inputs, read-only-root workflow, signed artifact manifest | 5.05 GB | 5.11 GB |

Each role passed **51/51 RV64 I test ELFs**, plus an expected-failure control,
in a fresh offline container. The selection builds 204 DAG tasks; this is not
204 tests or full RVI20U64 coverage. The cert signature workflow is this project's
prototype and does not issue an official ACT certificate.

Sizes are recorded Docker CLI display values; shared layers mean they cannot be
summed as physical disk use. See the [Phase 2 results and remaining scope](docs/phase2-status.md)
and [validation index](VALIDATION.md).

## Build the complete environment

Use an x86_64 Linux PC or x86_64 WSL2 with **Python 3.11+, Git, and a running
Docker daemon accessible to your user**. On WSL, keep the checkout in the Linux
filesystem. Downloads and installation need network access; acceptance runs
disable container networking. The initial GCC source build takes substantial
time. Run the baselines sequentially, especially on a 16 GB host.

```bash
git clone --branch phase2-act4 https://github.com/Gahao123/riscv-dev-env.git
cd riscv-dev-env

# Choose one baseline: 24.04 or 26.04.
version=24.04

# Layer 1: GCC/Newlib and the Phase 1 Spike release, including C/C++ smoke tests.
bash scripts/build.sh "$version"

# Layer 2: ACT4 dependencies, Sail, and the ACT4-compatible Spike revision.
bash scripts/build-act4.sh "$version"
bash scripts/check-act4.sh "$version"

# Layer 3: dev / ci / cert roles, reusing the installed tools.
bash scripts/build-profiles.sh "$version" all
bash scripts/check-profile.sh "$version" ci
bash scripts/check-profile.sh "$version" dev
```

Select `version=26.04` and run the same sequence for the other baseline. If the
matching `riscv-act4:ubuntu-<version>` integration image already exists, start at
Layer 3. If the role images already exist, run only the required checks.
Download scripts verify source archives automatically. Docker may reuse the
shared GCC build stage; a missing build cache can cause GCC to be rebuilt.

The resulting role tags are:

```text
riscv-act4:ubuntu-24.04-dev     riscv-act4:ubuntu-26.04-dev
riscv-act4:ubuntu-24.04-ci      riscv-act4:ubuntu-26.04-ci
riscv-act4:ubuntu-24.04-cert    riscv-act4:ubuntu-26.04-cert
```

Checks use two CPU equivalents, 4 GiB RAM, and 6 GiB including swap. Docker build
limits depend on the host builder; these verification limits do not automatically
limit the preceding image builds. Fresh outputs go under ignored `logs/` paths.
Set `ACT4_OUTPUT=/absolute/empty/path` to choose another result directory.

## Use the roles

Open the development environment with a persistent ACT4 source volume:

```bash
docker run --rm -it \
  --mount type=volume,src=act4-dev-2404,dst=/act4 \
  riscv-act4:ubuntu-24.04-dev
```

For the other baseline, select `ubuntu-26.04-dev` and a separate volume name.
The volume preserves source changes after the container exits. VS Code
configuration is supplied for both baselines; its GUI workflow has not yet been
tested. GDB loading and disassembly were tested.

CI can verify a separate standalone ACT4 checkout, including uncommitted edits:

```bash
ACT4_SOURCE=/absolute/path/to/act4-checkout \
ACT4_OUTPUT=/absolute/empty/ci-output \
  bash scripts/check-profile.sh 24.04 ci
```

Its dependency metadata must match the prepared image. Cert accepts only the
sealed packaged source, requires an external signing key and trusted public key,
and signs the generated artifact manifest after the tests pass. Follow the
[cert key, run, and independent verification instructions](PROFILES.md#cert-fixed-inputs-and-project-specific-signatures).

## Documentation and repository layout

| Entry | Contents |
|---|---|
| [Phase 2 status](docs/phase2-status.md) | Deliverables, six-image results, review checklist, remaining scope |
| [Role guide](PROFILES.md) | dev/ci/cert build, source policy, IDE configuration, signing and verification |
| [ACT4 integration](ACT4.md) | Pinned inputs, dependencies, offline runner and network options |
| [Validation index](VALIDATION.md) | Current results and historical build/test evidence |
| [Phase 1 guide](docs/phase1.md) | Toolchain versions, baseline builds and smoke tests |
| `Dockerfile`, `Dockerfile.act4`, `Dockerfile.profiles` | Three build layers |
| `scripts/`, `tools/`, `profiles/`, `tests/`, `patches/` | Build helpers, runners, regressions and attributed backport |
| `sources.lock.json`, `base-images.lock.json`, `act4.lock.json` | Source checksums, Ubuntu manifests, ACT4/tool revisions |
| `validation/` | Selected public reports, result JSON and logs |

Downloaded archives in `.cache/` and generated results in `logs/` are local,
ignored data. Private signing keys belong outside tracked files and images.
Ubuntu package repositories are not frozen, so pins and inventories do not
promise bit-identical rebuilds.

## Sources, credits, and AI assistance

- [ACT4](https://github.com/riscv/riscv-arch-test) supplies the tests, framework
  and configuration. Its pinned Dockerfile and Spike installation script informed
  the integration; [ACT4.md](ACT4.md) links the exact revisions.
- [RISC-V GNU toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain),
  [GCC](https://gcc.gnu.org/pub/gcc/releases/gcc-16.2.0/),
  [Spike](https://github.com/riscv-software-src/riscv-isa-sim) and
  [Sail](https://github.com/riscv/sail-riscv) retain their upstream authorship and licenses.
- Julien Olivain's upstream [Spike header fix](https://github.com/riscv-software-src/riscv-isa-sim/commit/0a7bb5403d0290cea8b2356179d92e4c61ffd51d)
  is credited in [the Phase 1 backport](patches/spike-gcc13-cstdint.patch).
  Source revisions and notices are retained in the locks and installed tools.

Codex provided substantial assistance with source research, image recipes,
scripts, runners, signature checks, documentation, and local build/test execution
through tooling. Validation records distinguish executed checks from remaining
work. The contributor reviews changes and remains responsible for correctness,
licensing, and claims made in upstream submissions.
