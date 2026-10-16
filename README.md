# RISC-V development environment — Phase 1 prototype

Prototype for [RISC-V DevPartners #47](https://github.com/riscv-admin/dev-partners/issues/47), prepared following Wei Wu's guidance on 2026-10-14. This repository provides image build recipes, source/version locks, and a small executable integration probe. Formal project acceptance criteria are still to be agreed with reviewers.

## Scope

- Host platform: `linux/amd64` initially.
- Runtime baselines: Ubuntu 24.04 LTS and Ubuntu 26.04 LTS.
- RISC-V GCC: 16.2.0, built with Newlib and installed under `/opt/riscv`.
- Spike: latest official release `v1.1.0`, with an attributed upstream GCC-header compatibility backport, installed under `/opt/spike`.
- Toolchain default: RV64GC / LP64D, without multilib. The freestanding probe explicitly uses RV64IMAC plus Zicsr / LP64; Spike v1.1.0 includes CSR instructions in its older I model.
- The cross toolchain is built once on Ubuntu 24.04 and reused in both runtime images; Spike is built separately on each runtime baseline. Both images need independent runtime verification.

This first prototype addresses the development container. CI-minimal images, locked certification environments, VM images, ACT4 integration, and real-board support are subsequent work. The smoke probe is not an architectural certification test.

## Why these versions

[Ubuntu 26.04 is an LTS release](https://ubuntu.com/about/release-cycle). [Spike's latest official release](https://github.com/riscv-software-src/riscv-isa-sim/releases/latest) is still v1.1.0 (2021); the newer master branch must not be described as the latest release tag. [GCC 16.2](https://gcc.gnu.org/releases.html) is the newest stable branch release as checked on 2026-10-14.

The [2026.08.27 RISC-V toolchain recipe](https://github.com/riscv-collab/riscv-gnu-toolchain/releases/tag/2026.08.27) pins GCC 16.1.0. We retain its Binutils/Newlib source revisions and explicitly substitute the official GCC 16.2.0 source archive through `--with-gcc-src`. This combination requires build/runtime verification; it is not represented as an upstream tested release bundle.

## Build and run

Use an x86_64 Linux PC or x86_64 WSL2 with Python 3.11+ and a running Docker daemon accessible to your user. Network access is needed for the source archives, base images, and Ubuntu packages. Keep the workspace in WSL's Linux filesystem when using WSL. About 2 build jobs are used by default; the initial source toolchain build is substantial and its duration depends on the machine.

Run these commands from the repository root:

```bash
python3 tools/fetch_sources.py
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

`base-images.lock.json` pins the official Ubuntu image manifests. The public ECR mirror was used because Docker Hub resolution timed out in the local WSL environment; its manifests were independently matched against Docker Hub. No system-wide DNS or Docker configuration was changed.

## Validation proposed for review

1. Build the image from pinned source archives, verifying checksums.
2. Confirm compiler version 16.2.0 and target `riscv64-unknown-elf`; retain the Spike source tag/commit and Ubuntu package inventory.
3. Compile a small freestanding RISC-V ELF and execute it through Spike's `tohost` interface, with a timeout treated as failure.
4. Execute an intentionally failing ELF and require a nonzero result, so errors are not silently accepted.
5. Repeat the probe in a fresh container as the default unprivileged user on both Ubuntu baselines.

Actual validation results and commands for rerunning the probes are in [VALIDATION.md](VALIDATION.md). The proposed checks do not establish complete compiler correctness, hardware coverage, ACT certification, or reproducibility of every binary bit across changing Ubuntu package repositories.

## Sources and credits

- [DevPartners task](https://github.com/riscv-admin/dev-partners/issues/47)
- [Existing ACT4 Dockerfile](https://github.com/riscv/riscv-arch-test/blob/act4/Dockerfile): reviewed as an existing integration reference; this prototype has its own build and probe scripts.
- [RISC-V GNU toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain)
- [GCC release archive and checksums](https://gcc.gnu.org/pub/gcc/releases/gcc-16.2.0/)
- [Spike](https://github.com/riscv-software-src/riscv-isa-sim)
- [Spike GCC 13 header fix](https://github.com/riscv-software-src/riscv-isa-sim/commit/0a7bb5403d0290cea8b2356179d92e4c61ffd51d), by Julien Olivain: the upstream one-line `<cstdint>` inclusion is backported in `patches/spike-gcc13-cstdint.patch`. The unpatched v1.1.0 release failed to build on both Ubuntu baselines; the backport changes header dependencies, not simulator execution logic.

Upstream components retain their own licenses; their source URLs and revisions are recorded in the source lock, and GCC/Spike license notices are included in the image.

## AI assistance

This initial prototype was developed with substantial assistance from Codex. Assistance covered source/version research, drafting and revising the Dockerfile, build/download scripts, source locks, smoke probes, and documentation, and executing local build and test commands through tooling.

The results in `VALIDATION.md` describe tests actually executed during that work. The contributor is reviewing the prototype for publication and remains responsible for correctness, licensing, and the scope of claims made when submitting it. Upstream code and the compatibility backport are credited separately above and in the patch. Future submissions to ACT4 should follow its contribution rules at the time of submission.
