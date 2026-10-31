# Phase 1: toolchain and Spike baseline

For the current ACT4 dev/ci/cert matrix, start with the [repository overview](../README.md)
and [role guide](../PROFILES.md). This page documents their prerequisite toolchain layer.

## Phase 1 baseline

- Host platform: `linux/amd64` initially.
- Runtime baselines: Ubuntu 24.04 LTS and Ubuntu 26.04 LTS.
- RISC-V GCC: 16.2.0, built with Newlib and installed under `/opt/riscv`.
- Spike: release `v1.1.0`, selected on 2026-10-14, with an attributed upstream GCC-header compatibility backport, installed under `/opt/spike`.
- Toolchain default: RV64GC / LP64D, without multilib. The freestanding probe explicitly uses RV64IMAC plus Zicsr / LP64; Spike v1.1.0 includes CSR instructions in its older I model.
- The cross-toolchain build stage always uses Ubuntu 24.04, and both runtime images consume its installed artifacts. Docker can reuse that stage when its build cache is available; without a cache hit, it will rebuild the toolchain. Spike is built separately on each runtime baseline. Both images need independent runtime verification.

## Why these versions

[Ubuntu 26.04 is an LTS release](https://ubuntu.com/about/release-cycle). The 2026-10-14 version check selected [Spike v1.1.0](https://github.com/riscv-software-src/riscv-isa-sim/releases/tag/v1.1.0) and [GCC 16.2](https://gcc.gnu.org/releases.html). These recorded pins are retained across builds; version updates require a lock-file change and validation.

The [2026.08.27 RISC-V toolchain recipe](https://github.com/riscv-collab/riscv-gnu-toolchain/releases/tag/2026.08.27) pins GCC 16.1.0. We retain its Binutils/Newlib source revisions and explicitly substitute the official GCC 16.2.0 source archive through `--with-gcc-src`. This combination requires build/runtime verification; it is not represented as an upstream tested release bundle.

## Build and run

Use an x86_64 Linux PC or x86_64 WSL2 with Python 3.11+ and a running Docker daemon accessible to your user. Network access is needed for the source archives, base images, and Ubuntu packages. Keep the workspace in WSL's Linux filesystem when using WSL. About 2 build jobs are used by default; the initial source toolchain build is substantial and its duration depends on the machine.

Run these commands from the repository root:

```bash
bash scripts/build.sh 24.04
bash scripts/build.sh 26.04

# Open a shell in the Ubuntu 24.04 environment.
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD:/workspace" riscv-dev:ubuntu-24.04
```

`fetch_sources.py` downloads and verifies the source archives. Each `build.sh` invocation also performs that step, builds its image, and runs the smoke test in a fresh container. After both builds succeed, the two local image tags are `riscv-dev:ubuntu-24.04` and `riscv-dev:ubuntu-26.04`.

To open the Ubuntu 26.04 environment instead:

```bash
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$PWD:/workspace" riscv-dev:ubuntu-26.04
```

The images contain Ubuntu userspace, build tools, a C/C++ bare-metal cross compiler and Newlib, and Spike. Containers share the host kernel. The default command opens a shell; the current host directory is mounted at `/workspace`. With `--rm`, changes outside that mount disappear when the container exits; files written to the mount remain on the host, and the built images remain available. Board-specific Linux sysroots and deployment scripts are outside this initial scope.

`base-images.lock.json` pins the official Ubuntu image manifests. The public ECR mirror was used during the original WSL validation; its manifests were independently matched against Docker Hub.

## Recorded checks

The root `.dockerignore` includes only the locked source archives and Phase 1
build/probe inputs. Update its archive entries when changing source filenames
in `sources.lock.json`. ACT4 and role builds assemble separate contexts.

The [original 2026-10-14 results](../validation/phase1-20261014.md) and
[public-checkout revalidation](../validation/public-recheck-20261016.md) record
C/C++ smoke tests, expected failure propagation, normal-user execution, and
mount behavior. The current evidence index is [VALIDATION.md](../VALIDATION.md).
