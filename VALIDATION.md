# Validation results

Date: 2026-10-14 (Asia/Shanghai).

Both Phase 1 prototype development images built and passed executable integration probes in fresh containers. These are local results, not official ACT certification or an agreed final acceptance standard.

This report is intended for users and reviewers to understand what was tested and the limits of those results. Build instructions are in [README.md](README.md); the logs under `validation/` record the run reported here.

## Rerun the integration probes

After building both images, run:

```bash
docker run --rm riscv-dev:ubuntu-24.04 riscv-smoke-test
docker run --rm riscv-dev:ubuntu-26.04 riscv-smoke-test
```

Each command uses a fresh container and the default unprivileged image user. Success requires the C and C++ programs to exit 0 and the deliberate failure to exit 1; a timeout fails the probe. `scripts/build.sh` also runs this probe automatically after each image build. These commands rerun the integration check; they do not rebuild the images or refresh the recorded logs.

## Environment and outcomes

| Check | Ubuntu 24.04.5 LTS | Ubuntu 26.04.1 LTS |
|---|---|---|
| Host/container platform | linux/amd64 | linux/amd64 |
| Final image build | PASS | PASS |
| GCC and G++ version | 16.2.0 | 16.2.0 |
| Compiler target | riscv64-unknown-elf | riscv64-unknown-elf |
| Spike | v1.1.0 + attributed header backport | v1.1.0 + attributed header backport |
| C ELF compilation and Spike execution | PASS | PASS |
| C++20 std::array probe compilation and execution | PASS | PASS |
| Deliberately failing ELF | exit 1, expected | exit 1, expected |
| Fresh container as default user | PASS, uid 1001 | PASS, uid 1001 |

The probe uses RV64IMAC plus Zicsr / LP64 and a freestanding `tohost` exit interface. Compiler default libraries are RV64GC / LP64D, so these probes deliberately do not link target standard libraries. Newlib and target C++ libraries were built, but their complete runtime behavior is not covered by this probe.

## Verified inputs and build organization

- Ubuntu mirror manifest digests independently matched Docker Hub's official Ubuntu manifests.
- All five source archives were checksum verified; GCC matched the official SHA-512 list.
- GCC 16.2.0 and Newlib were built from source on Ubuntu 24.04. The same compiler artifact was reused in both runtime baselines, with independent runtime probes. GCC was not separately rebuilt on Ubuntu 26.04.
- Unmodified Spike v1.1.0 failed to compile on both baselines due to the missing `<cstdint>` include in `fesvr/device.h`.
- Julien Olivain's upstream commit [0a7bb540](https://github.com/riscv-software-src/riscv-isa-sim/commit/0a7bb5403d0290cea8b2356179d92e4c61ffd51d) was backported; standalone and integrated Spike builds then passed on both baselines.
- After the initial compiler build, the ignored `--disable-qemu` configure argument was removed. Rerunning configure without it produced a byte-for-byte identical generated Makefile. The compiler was not rebuilt for this nonfunctional cleanup.

Runtime logs and machine-readable image/version records are in `validation/`. Full runtime-image compilation logs are retained in the local working audit directory; the source compiler's first build was captured in the tool transcript rather than a complete saved log file.

The tiny bare-metal linker layout emits a warning about a combined RWX load segment. Memory permissions are not an assertion of this arithmetic/startup probe.

## Not covered

- Full GCC regression tests or all target standard-library functions.
- Full ACT4 integration, architectural certification, ISA/ABI coverage matrices, or processor correctness.
- Real RISC-V boards, arm64/riscv64 host images, VM images, Linux board sysroots, or the research memory-safety tool.
- CI-minimal and locked certification image variants.
- Bit-for-bit binary reproducibility across changing Ubuntu apt repositories.

Reviewer agreement on acceptance criteria and subsequent milestones remains open.
