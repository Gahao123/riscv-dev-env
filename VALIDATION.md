# Validation index

Current role-matrix validation: **2026-10-31**, Linux/x86_64 Docker on WSL2.
The [Phase 2 status](docs/phase2-status.md) summarizes deliverables and review
scope. The [README](README.md) gives the complete build sequence, and
[PROFILES.md](PROFILES.md) gives role-specific checks.

## Current dev / ci / cert results

| Baseline | dev | ci | cert | Evidence |
|---|---|---|---|---|
| Ubuntu 24.04 | 51/51 | 51/51 | 51/51 | [Report](validation/profiles-2404-20261031.md), [matrix JSON](validation/profiles-2404-20261031.json) |
| Ubuntu 26.04 | 51/51 | 51/51 | 51/51 | [Report](validation/profiles-2604-20261031.md), [matrix JSON](validation/profiles-2604-20261031.json) |

Every role was tested offline in a fresh container as UID 1001, with two workers,
4 GiB RAM, and 6 GiB including swap. Every run also rejected an incomplete
one-instruction execution. The pinned selection is 51 RV64 I test ELFs;
204 build DAG tasks are not 204 tests.

The reports also record:

- dev: GDB recognizes the generated RISC-V ELF and disassembles its entry point;
  both IDE configurations parse, but no IDE GUI or live remote debugging was tested.
- ci: another upstream revision passes; a broken run command causes all 51 tests
  to fail and the host wrapper to return 1; dependency drift is rejected.
- cert: sealed-input checks, read-only-root runs, external test-key signing,
  independent signature/hash verification, and rejection of modified inputs/results.
- Six OpenSSL signature boundary regressions, ShellCheck, and Python core Ruff checks.
- 26.04 compatibility: prior 24.04 images are unchanged, the original CLI syntax
  passes, and the 24.04 cert image verifies the 26.04 artifact bundle.

These role tests ran on the same host. A second-machine Phase 2 validation is
not recorded here. Existing images were reused for compatibility checks; those
checks are not additional clean source builds.

## Earlier milestones

Historical reports describe their own date and scope. Their remaining-work
sections should not be read as the current project status.

| Date | Milestone | Report and machine-readable record |
|---|---|---|
| 2026-10-14 | Phase 1 Ubuntu 24.04/26.04 C/C++ smoke probes | [Report](validation/phase1-20261014.md), [JSON](validation/results.json) |
| 2026-10-16 | Public-checkout Phase 1 revalidation, including staged 26.04 build limitations | [Report](validation/public-recheck-20261016.md), [JSON](validation/public-recheck-20261016.json) |
| 2026-10-24 | Initial manual Ubuntu 24.04 ACT4 integration | [Report](validation/act4-2404-20261024.md), [JSON](validation/act4-2404-20261024.json) |
| 2026-10-24 | Automated Ubuntu 24.04 ACT4 image and offline verification | [Report](validation/act4-auto-2404-20261024.md), [JSON](validation/act4-auto-2404-20261024.json) |
| 2026-10-25 | Automated Ubuntu 26.04 ACT4 image and 24.04 regression | [Report](validation/act4-auto-2604-20261025.md), [JSON](validation/act4-auto-2604-20261025.json) |

Each report links its selected logs and result records. Full generated ELFs,
signed bundles, and detailed local audit/build directories are outside Git.
Recorded image IDs identify the exact local runs; this repository currently
publishes recipes and records rather than registry-hosted project images.

## Scope and reruns

The current record covers the pinned RV64 I integration on Spike. Full RVI20U64
coverage, physical hardware, VM images, other host architectures, official final
suite/signing policy, full GCC regressions, and IDE GUI sessions remain unverified.
The local Ed25519 identity demonstrates artifact integrity and is not an ACT
authority. Ubuntu package repositories remain live; bit-identical rebuilds are
not claimed.

To rerun existing role images, select the baseline and use a fresh output:

```bash
ACT4_OUTPUT="$PWD/logs/my-new-2404-ci-run" \
  bash scripts/check-profile.sh 24.04 ci
ACT4_OUTPUT="$PWD/logs/my-new-2604-ci-run" \
  bash scripts/check-profile.sh 26.04 ci
```

Choose a new empty path for every rerun. Cert additionally requires externally
supplied signing and trusted verification keys; use the [role guide](PROFILES.md).
