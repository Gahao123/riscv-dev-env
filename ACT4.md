# Automated ACT4 integration on Ubuntu LTS

This Phase 2 integration prototype reuses the Phase 1 GCC
16.2.0/Newlib installation and builds self-checking tests from a pinned ACT4
checkout on Ubuntu 24.04 and 26.04. The separate [dev/CI/cert role images](PROFILES.md)
build on these integration images.

Start with the [README build sequence](README.md#build-the-complete-environment)
for all three image layers, or the [Phase 2 status](docs/phase2-status.md) for the
current deliverables and review scope.

The [automated-image validation record](validation/act4-auto-2404-20261024.md)
reports 51 passing test ELFs and an expected-failure control in a fresh offline
container. The [Ubuntu 26.04 validation record](validation/act4-auto-2604-20261025.md)
covers the same pinned suite on the second baseline. The earlier
[manual integration record](validation/act4-2404-20261024.md) is retained separately.

## Pinned inputs

The exact revisions, archive checksums, and environment versions are recorded in
[`act4.lock.json`](act4.lock.json).

- ACT4: [`6da7a898`](https://github.com/riscv/riscv-arch-test/tree/6da7a898d508fee6f741777840c05e71df561f0c).
- Configuration: upstream `config/spike/spike-RVI20U64/test_config.yaml`.
- Selected suite: `I` only, for RV64.
- Sail reference model: official 0.16 Linux/x86_64 release asset, checked against
  its GitHub release SHA-256 digest.
- Spike for ACT4: `2c300cd90eb74bb79f3fcdd58596a6f8d842d01c`, installed under
  `/opt/spike-act4`. This is the commit selected by ACT4's
  [`install-spike.sh`](https://github.com/riscv/riscv-arch-test/blob/6da7a898d508fee6f741777840c05e71df561f0c/.github/scripts/install-spike.sh).
  The SoftFloat submodule revision is pinned separately.
- Ruby, Bundler, uv, and Python dependencies follow the pinned ACT4 checkout's
  `.mise.toml`, `uv.lock`, and `framework/src/act/data/Gemfile.lock`.

The dependency preparation follows the mise/uv/Bundler approach in ACT4's
[upstream Dockerfile](https://github.com/riscv/riscv-arch-test/blob/6da7a898d508fee6f741777840c05e71df561f0c/Dockerfile).
This repository adds the Phase 1 image reuse, checked tool archives, separate
Spike installation, and offline integration/failure-control commands.

The original Phase 1 Spike v1.1.0 remains under `/opt/spike`. It rejects the
`--instructions` option used by the current upstream run command. The ACT4
experiment therefore uses a separate, CI-pinned simulator revision. This is a
pinned development commit, not a newer official release tag.

## Run the integration probe

Start with the matching Phase 1 `riscv-dev:ubuntu-<version>` image, built by
`bash scripts/build.sh <version>`, Python 3.11+, and Docker on an x86_64 Linux/WSL
host. From this repository's root, choose one baseline and run sequentially:

```bash
bash scripts/build-act4.sh 24.04
bash scripts/check-act4.sh 24.04

# Or use the Ubuntu 26.04 Phase 1 image:
bash scripts/build-act4.sh 26.04
bash scripts/check-act4.sh 26.04
```

The first command verifies the locked Spike, SoftFloat, Sail, and mise archives,
then builds `riscv-act4:ubuntu-<version>` using `Dockerfile.act4`. Both scripts
default to 24.04 when the version argument is omitted. The recipe fetches the exact
ACT4 Git commit and installs the upstream Ruby/Python dependencies. GCC is reused
from Phase 1. The Spike source/object directory is removed in its build layer.
Downloads need network access; Ubuntu packages are recorded in the image but
are not frozen to a dated archive. This is not a bit-for-bit reproducible build.

The second command starts a fresh container with **networking disabled**, two
CPU equivalents, a 4 GiB memory limit and a 6 GiB combined memory/swap limit.
It builds/runs the suite as `riscv` (UID 1001), then checks that a deliberately
incomplete run is rejected. Results, per-test summaries and logs go under
`logs/act4-<version>-<UTC timestamp>/`. Output ownership is returned to the calling host
user. `ACT4_OUTPUT=/absolute/path` chooses a different output directory. Use an
empty directory for evidence of a fresh test build. These limits apply to the
validation container; Docker build resource limits depend on the host builder.

`PHASE1_IMAGE`, `ACT4_IMAGE`, and `BUILD_JOBS` override the base tag, resulting
image tag, and compilation parallelism (default 2). The custom image must match
the selected Ubuntu version. Only Ubuntu 24.04 and 26.04 on linux/amd64 are
supported so far. Build and validation both check the actual OS version. Build
scripts preserve the Phase 1 tags and give the ACT4 images separate version tags.

Standard `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` variables are forwarded as
Docker's predefined build arguments. If a proxy on host loopback cannot be
reached from the build network, Linux users can set `ACT4_BUILD_NETWORK=host`.
This is optional and depends on the Docker host; no machine-specific proxy is
part of the recipe. Validation remains offline.

For an interactive shell:

```bash
docker run --rm -it riscv-act4:ubuntu-24.04 bash
# Choose riscv-act4:ubuntu-26.04 for the other baseline.
# Inside the container:
riscv-act4-probe
```

[`scripts/run-act4-probe.sh`](scripts/run-act4-probe.sh) runs inside the resulting
environment. For reference, its prerequisites are:

1. The pinned ACT4 Git checkout at `/act4`, owned by the testing user.
2. Phase 1 GCC/Newlib on `PATH`.
3. Sail at `/opt/sail` and the CI-pinned Spike at `/opt/spike-act4`.
4. `mise` under `$HOME/.local/bin`, the pinned ACT4 tools installed, Python
   workspace synchronized, and the Ruby bundle installed.
5. This project's lock copied to `/usr/share/riscv-dev-env/act4.lock.json`.
6. The Spike commit recorded in
   `/opt/spike-act4/share/source-revision.txt`.

Alternatively, run the script from a provisioned source checkout:

```bash
bash scripts/run-act4-probe.sh
```

The runner checks the recorded versions, generates the `I` tests using upstream
Make targets, compiles signature-generating ELFs, uses Sail to obtain expected
results, and builds self-checking ELFs. It then runs the upstream `run_tests.py`
with two workers and a 30-second per-test timeout. Empty ELF output is an error.
Both simulator exit status and the upstream `RVCP-SUMMARY` result are checked by
the upstream runner.

`ACT4_ROOT`, `ACT4_LOCK`, `ACT4_WORKDIR`, `ACT4_JOBS`, and `ACT4_TEST_TIMEOUT` can
override the corresponding paths and limits. Keep build outputs in a mounted
directory if they must survive container removal. Logs and the test selection
list are under `$ACT4_WORKDIR/spike-RVI20U64/`.

## Scope

The selected `I` suite exercises the initial integration path. It does not
establish that all extensions in the RVI20U64 configuration have passed, complete
an architectural certification, or validate a physical processor. The first
[Ubuntu 24.04 and 26.04 dev/CI/cert prototypes](PROFILES.md) build on the matching
integration seeds. VM images, broader test coverage, and upstream-approved
certification/signing policy remain subsequent work.

ACT4 and its test sources retain their upstream licenses and authorship. This
repository supplies the environment integration and runner; it does not claim
authorship of the upstream tests, reference model, or simulator.

Codex assisted with researching the pinned upstream setup, preparing the
image recipe, installation/validation scripts and records, and executing local
validation.
