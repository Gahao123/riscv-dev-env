# Phase 2 container deliverables

Status as of **2026-10-31**: the Ubuntu 24.04 and 26.04 dev/ci/cert container
prototypes are implemented and locally validated, ready for review against
[DevPartners #47](https://github.com/riscv-admin/dev-partners/issues/47).
Formal acceptance criteria and the VM/official-certification scope remain to
be agreed with the ACT team.

## What was delivered

| Component | Implementation | Recorded result |
|---|---|---|
| Two Ubuntu baselines | Pinned manifests and shared GCC 16.2.0/Newlib artifacts | Both baselines run the selected tests |
| ACT4 integration | Pinned ACT4, CI-selected Spike, Sail, Python/Ruby dependencies | Offline generation, reference signatures, ELF compilation and execution |
| dev | Native build tools, editor, GDB multiarch, two IDE configurations | Baseline and GDB loading/disassembly pass; IDE configuration parses |
| ci | Noninteractive runner, external source support, recorded revision | Baseline and alternate revision pass; broken source returns failure |
| cert | Sealed runtime/source inventory, read-only-root wrapper, external-key signing | Baseline and signatures/hashes pass; tampering is rejected |
| Reusable automation | Version-selectable build/check scripts and JSON/log artifacts | Original 24.04 CLI remains compatible |

The dependency layers are:

```text
Dockerfile                  -> riscv-dev:ubuntu-<version>
  GCC/Newlib + Phase 1 Spike
Dockerfile.act4              -> riscv-act4:ubuntu-<version>
  ACT4 + Sail + ACT4-pinned Spike + language dependencies
Dockerfile.profiles          -> riscv-act4:ubuntu-<version>-{dev,ci,cert}
  Curated runtime + role-specific tools and source/signature policy
```

Role preparation reuses installed GCC and Spike. It strips host Spike debug
sections, excludes tool installers/download caches, and retains native UDB runtime
dependencies. All six roles preserve the same GCC executable SHA-256.

## Six-image validation matrix

| Local image | Docker display size | Offline RV64 I | Early-stop control |
|---|---|---|---|
| `riscv-act4:ubuntu-24.04-dev` | 5.48 GB | 51/51 | Rejected |
| `riscv-act4:ubuntu-24.04-ci` | 5.05 GB | 51/51 | Rejected |
| `riscv-act4:ubuntu-24.04-cert` | 5.05 GB | 51/51 | Rejected |
| `riscv-act4:ubuntu-26.04-dev` | 5.63 GB | 51/51 | Rejected |
| `riscv-act4:ubuntu-26.04-ci` | 5.11 GB | 51/51 | Rejected |
| `riscv-act4:ubuntu-26.04-cert` | 5.11 GB | 51/51 | Rejected |

Original integration images display 9.86 GB (24.04) and 9.97 GB (26.04).
All sizes use the same Docker CLI metric. Shared layers prevent summing rows as
disk use; retaining original images/cache means this does not measure space freed.

Tests ran as UID 1001 without network, with two workers, 4 GiB RAM and 6 GiB
including swap. The selected suite is `I` under upstream
`config/spike/spike-RVI20U64/test_config.yaml`: 51 test ELFs and 204 build DAG
tasks. It is a subset of the configured architectural profile.

Detailed provenance, versions, image IDs and logs:

- Ubuntu 24.04: [report](../validation/profiles-2404-20261031.md), [matrix JSON](../validation/profiles-2404-20261031.json).
- Ubuntu 26.04: [report](../validation/profiles-2604-20261031.md), [matrix JSON](../validation/profiles-2604-20261031.json).
- Earlier builds: [validation index](../VALIDATION.md).

## Behavior checked beyond a successful run

- **Failure detection:** one-instruction Spike execution produces no success
  summary. The upstream runner returns 1 even though Spike returns 0; every
  baseline acceptance run requires this rejection.
- **CI source handling:** another upstream revision passes. A broken run command
  makes all 51 main tests fail and causes a host exit of 1. Changed dependency
  metadata is rejected.
- **Cert boundaries:** changed tool inputs, source overrides and modified signed
  summaries are rejected. Six OpenSSL unit checks cover valid signatures,
  changed artifacts, added hidden files, changed manifests, wrong trusted keys
  and unsafe parent paths.
- **Compatibility:** 26.04 checks preserve earlier 24.04 role image IDs. The
  original 24.04 CLI passes; its cert verifier accepts the signed 26.04 bundle
  using the externally trusted public key.
- **Development tools:** GDB loads the generated ELF and disassembles its entry
  point; both VS Code configurations parse. GUI sessions and live Spike remote
  debugging were not tested.

## Reproduce and review

Start with the [README build sequence](../README.md#build-the-complete-environment),
then use [PROFILES.md](../PROFILES.md) for external-source CI and cert keys/runs.
Source pins are in `sources.lock.json` and `act4.lock.json`; Ubuntu image
manifests are in `base-images.lock.json` at the repository root.

| Review item | State |
|---|---|
| Two baselines × three role recipes and local test evidence | Complete |
| Build/check instructions and result index | Complete |
| Phase 2 validation on another host | Pending; Phase 1 revalidation does not cover this |
| ACT team agreement on required tests and signing format/trust policy | Pending |
| VM requirement and packaging scope | Pending agreement; no VM image built |
| Upstream submission and CI workflow/registry hand-off | Subsequent integration work |

Cert signs **the generated artifact manifest after successful testing**, using an
externally supplied local Ed25519 test identity. This does not establish an
ACT-approved final suite release/signing process or issue an official certificate.
Ubuntu repositories are live; bit-identical rebuilds and hostile-host protection
are outside the recorded checks.

## Evidence and local data

Build helpers, tests, locks, the attributed patch and historical runs are part
of the deliverable. Equal output from separate tests is retained as evidence for
each run. Phase 1 has a dedicated [guide](phase1.md) and
[historical report](../validation/phase1-20261014.md).

Source archive caches and generated output are ignored local data; signing keys
must remain outside tracked files and images. The root Docker build context
includes only the locked source archives and required Phase 1 build/probe files.
ACT4 and role scripts assemble their own contexts. Codex assisted with
implementation, validation and documentation; upstream credits/licenses remain.
