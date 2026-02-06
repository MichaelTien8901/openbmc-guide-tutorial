---
layout: default
title: Jenkins CI/CD Infrastructure
parent: Appendix
nav_order: 1
difficulty: intermediate
prerequisites:
  - environment-setup
  - first-build
---

# OpenBMC Jenkins CI/CD Infrastructure

## Overview

OpenBMC uses a Jenkins-based CI/CD system — not GitHub Actions — for all build and test automation. The infrastructure is centralized in the [openbmc/openbmc-build-scripts](https://github.com/openbmc/openbmc-build-scripts) repository and operates at `https://jenkins.openbmc.org`, tightly integrated with Gerrit for code review.

This appendix documents the CI architecture, job structure, Docker test infrastructure, and Gerrit integration.

## Architecture

### Two-Tier CI Model

OpenBMC implements a two-tier testing strategy:

```
┌─────────────────────────────────────────────────────────────┐
│                  Tier 1: Repository-Level CI                │
│                  (fast, per-commit, minutes)                │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ Code Format  │  │  Build Repo  │  │   Unit Tests      │  │
│  │ (14 linters) │  │ (meson/cmake)│  │ (meson test/ctest)│  │
│  └──────────────┘  └──────────────┘  └───────────────────┘  │
│  ┌──────────────┐  ┌──────────────┐                         │
│  │   cppcheck   │  │  valgrind    │  (optional analysis)    │
│  └──────────────┘  └──────────────┘                         │
├─────────────────────────────────────────────────────────────┤
│                  Tier 2: System-Level CI                    │
│                  (slow, integration, hours)                 │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ BitBake Full │  │  QEMU Boot   │  │ Robot Framework   │  │
│  │ Image Build  │  │  (ARM emu)   │  │ Integration Tests │  │
│  └──────────────┘  └──────────────┘  └───────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Tier 1: Repository-Level CI

Triggered on every Gerrit patchset upload. Runs via `run-unit-test-docker.sh` → `unit-test.py`:

- **Code formatting** — 14 linters/formatters (clang-format, black, shellcheck, eslint, prettier, markdownlint, etc.)
- **Build** — compiles the changed repo using its build system (meson, cmake, or autotools)
- **Unit tests** — runs `meson test` / `make check` / `ctest`
- **Static analysis** — optional cppcheck, valgrind, sanitizer, clang-tidy passes
- **Coverage reports** — generated for tracking test coverage
- Runs on both x86_64 and ppc64le architectures

### Tier 2: System-Level CI

Full image build + QEMU boot + Robot Framework testing:

1. **BitBake image build** (`build-setup.sh`) — full Yocto build for a target machine
2. **QEMU boot** (`boot-qemu.sh`) — boots the firmware image in ARM emulation
3. **Robot Framework tests** (`run-robot.sh`) — Redfish API, IPMI, SSH, boot validation tests
4. Duration: tens of minutes to hours

## Jenkins Job Map

| Job | Script | Purpose |
|-----|--------|---------|
| `ci-repository` | `run-unit-test-docker.sh` | Unit tests for any repo |
| `ci-repository-ppc64le` | `run-unit-test-docker.sh` | Unit tests on ppc64le |
| `ci-openbmc` | `build-setup.sh` | Full BitBake image build |
| `ci-build-seed` | `jenkins/build-seed` | Pre-populate sstate caches for ~19 machines |
| `run-ci-in-qemu` | `run-qemu-robot-test.sh` | Boot QEMU + Robot tests |
| `openbmc-userid-validation` | `jenkins/userid-validation` | Gerrit user authorization |
| `latest-master` | `build-setup.sh` | Nightly full image builds |
| `latest-master-sdk` | `build-setup.sh` | Nightly SDK builds |
| `latest-qemu-ppc64le` | `qemu-build.sh` | Build QEMU for ppc64le |
| `latest-qemu-x86` | `qemu-build.sh` | Build QEMU for x86 |
| `latest-unit-test-coverage` | `get_unit_test_report.py` | Coverage reports |
| `release-tag` | `build-setup.sh` | Tagged release builds |
| `ci-openbmc-build-scripts` | `jenkins/run-build-script-ci` | Self-test of build scripts |

## Repository Structure

```
openbmc-build-scripts/
├── build-setup.sh                  # Full BitBake image build (Tier 2)
├── run-unit-test-docker.sh         # Unit test Docker runner (Tier 1)
├── run-qemu-robot-test.sh          # QEMU + Robot Framework test runner
├── run-rootfs-size-docker.sh       # Root filesystem size analysis
├── qemu-build.sh                   # QEMU compilation in Docker
├── jenkins/
│   ├── build-seed                  # Seed job for all machine builds
│   ├── run-build-script-ci         # Self-test of build scripts
│   ├── run-meta-ci                 # Meta-layer CI (deprecated)
│   └── userid-validation           # Gerrit user authorization check
├── scripts/
│   ├── build-unit-test-docker      # Docker image builder (Python)
│   ├── unit-test.py                # Unit test runner (Python)
│   ├── dbus-unit-test.py           # D-Bus session test wrapper
│   ├── format-code.sh              # 14-tool code formatting suite
│   ├── boot-qemu.sh               # QEMU launch script
│   ├── boot-qemu-test.exp          # Expect-based QEMU boot validation
│   ├── test-qemu                   # Multi-platform QEMU smoke test
│   ├── run-robot.sh                # Robot Framework test executor
│   ├── get_unit_test_report.py     # Unit test coverage reporter
│   └── repositories.txt            # Test repository list
├── config/
│   ├── .gitlint                    # Commit message rules
│   ├── eslint.config.js            # JSON linting
│   ├── markdownlint.yaml           # Markdown linting
│   └── prettierrc.yaml             # Multi-format formatting
└── tools/
    ├── owners                      # OWNERS file parser for Gerrit
    └── config-clang-tidy           # Clang-tidy configuration
```

## Gerrit Integration

### Workflow

OpenBMC uses Gerrit (not GitHub PRs) for code review. Jenkins integrates via the Gerrit Trigger plugin:

```
Developer                    Gerrit                     Jenkins
   │                           │                          │
   │── git push refs/for/master ──>                       │
   │                           │── Trigger Event ────────>│
   │                           │                          │
   │                           │<── userid-validation ────│
   │                           │    (check CI auth)       │
   │                           │                          │
   │                           │    IF authorized:        │
   │                           │<── ok-to-test=1 ─────────│
   │                           │<── ok-to-test=0 ─────────│
   │                           │    (reset to prevent     │
   │                           │     infinite triggers)   │
   │                           │                          │
   │                           │── Trigger CI Jobs ──────>│
   │                           │    ci-repository         │
   │                           │    ci-openbmc            │
   │                           │                          │
   │                           │<── Verified +1/-1 ───────│
   │<── Review notification ───│                          │
```

### User Authorization

The `userid-validation` script is a critical gatekeeper. When a Gerrit patchset is uploaded:

1. **Identify the committer** — uses `gerrit query` via SSH to get the uploader's username
2. **Reset the vote** — sets `ok-to-test=0` to prevent Jenkins infinite retriggers
3. **Add OWNERS-based reviewers** — parses OWNERS files and automatically adds reviewers via the Gerrit REST API
4. **Check group membership** — enumerates members of 60+ organization-specific `ci-authorized` groups:
   - `amd/ci-authorized`, `ampere/ci-authorized`, `arm/ci-authorized`, `aspeed/ci-authorized`
   - `google/ci-authorized`, `ibm/ci-authorized`, `intel/ci-authorized`, `nvidia/ci-authorized`
   - And 50+ more organizations
5. **Grant or deny CI** — if found, sets `ok-to-test=1` with "User approved, CI ok to start", then immediately resets to `ok-to-test=0`

{: .note }
This implements the delegated CI authorization model from the [ci-authorization design document](https://github.com/openbmc/docs/blob/master/designs/ci-authorization.md), where each organization manages its own `ci-authorized` Gerrit group.

## Unit Testing Pipeline

The unit testing pipeline involves three layers:

### Layer 1: Docker Entry Point (`run-unit-test-docker.sh`)

- Validates `WORKSPACE`, build scripts, and test package directories
- Invokes `scripts/build-unit-test-docker` to build/cache the Docker image
- Launches a Docker container with the test package mounted
- Inside the container, runs `dbus-unit-test.py` → `unit-test.py`

Key environment variables:

| Variable | Purpose |
|----------|---------|
| `UNIT_TEST_PKG` | Repository being tested |
| `BRANCH` | Branch to build from (defaults to master) |
| `TEST_ONLY` | Skip analysis tools |
| `NO_FORMAT_CODE` | Skip formatting checks |
| `NO_CPPCHECK` | Skip static analysis |
| `INTERACTIVE` | Run bash shell for debugging |

### Layer 2: Docker Image Builder (`scripts/build-unit-test-docker`)

- Builds 30+ OpenBMC dependency packages in parallel using threads
- Core libraries: sdbusplus, phosphor-dbus-interfaces, phosphor-logging, libpldm
- Each package specifies build type: autoconf, cmake, meson, make, or custom
- Uses Docker content-hash-based caching with `YYYY-Www` (ISO week) tagging
- Supports both Docker and Podman container runtimes

### Layer 3: Test Runner (`scripts/unit-test.py`)

- Detects build system: Meson, Autotools, or CMake
- Implements a `DepTree` class for dependency ordering with cycle detection
- For the target package:
  1. Downloads and builds all dependencies
  2. Configures with testing flags enabled
  3. Builds the software
  4. Executes unit tests
  5. Runs optional analysis: cppcheck, valgrind, sanitizers, clang-tidy
  6. Generates code coverage reports

### Layer 4: D-Bus Wrapper (`scripts/dbus-unit-test.py`)

- Launches a `dbus-daemon` in session mode with a custom socket
- Sets `DBUS_SESSION_BUS_ADDRESS` for OpenBMC services that require D-Bus
- Cleans up the D-Bus daemon on exit

## Full Image Build (`build-setup.sh`)

Handles the complete BitBake image build for Tier 2 CI:

- Generates a Dockerfile for either Fedora or Ubuntu containers
- Configures locale, proxy settings, user/group mappings
- Creates an inner build script that runs BitBake inside the container
- Supports `CONTAINER_ONLY` mode for just building the Docker image
- Handles both Docker and Podman runtimes

## QEMU Testing Pipeline

### QEMU Build (`qemu-build.sh`)

- Compiles QEMU from source in a Docker container (Ubuntu Jammy base)
- Targets ARM architecture with minimal features (no X11, USB, VNC)

### QEMU Boot (`scripts/boot-qemu.sh`)

- Launches QEMU with configurable architecture (ppc64le or x86_64)
- Port forwarding: SSH (22), HTTPS (443), HTTP (80), IPMI (623)
- Handles multiple image formats: `.ubi.mtd`, `.static.mtd`, `rootfs.ext4`
- Machine-specific configurations (e.g., Tacoma requires four NICs)

### QEMU Boot Validation (`scripts/boot-qemu-test.exp`)

- Expect script that spawns `boot-qemu.sh`
- Waits for login prompt, authenticates with `root/0penBmc`
- Outputs `OPENBMC-READY` marker when system is booted

### Robot Framework Tests (`run-qemu-robot-test.sh`)

- Builds a Docker image with QEMU and Robot Framework pre-installed
- Starts QEMU container in detached mode
- Polls Docker logs for `OPENBMC-READY` marker (timeout: 300s default)
- Launches a separate Robot test container against the QEMU instance
- Tests include: Redfish API, IPMI, SSH connectivity, boot validation
- Supports architectures: ppc64le, x86_64, aarch64

### Multi-Platform Smoke Test (`scripts/test-qemu`)

Downloads pre-built firmware from Jenkins and validates login for:

| Platform | SoC |
|----------|-----|
| Palmetto | AST2400 |
| Romulus  | AST2500 |
| P10BMC   | AST2600 |

## Code Formatting Suite

`scripts/format-code.sh` enforces consistency across 14 tools:

| Tool | File Types | Purpose |
|------|------------|---------|
| `clang_format` | C/C++ | Code formatting |
| `clang_tidy` | C/C++ | Static analysis config |
| `black` | Python | Code formatting (79-char lines) |
| `flake8` | Python | Style checking |
| `isort` | Python | Import organization |
| `beautysh` | bash/sh | Shell script formatting |
| `shellcheck` | bash/sh | Shell static analysis |
| `eslint` | JSON | JSON linting |
| `prettier` | JSON/MD/YAML | Multi-format beautifier |
| `markdownlint` | Markdown | Markdown validation |
| `meson` | Meson files | Build file formatting |
| `commit_gitlint` | Commit messages | Format validation (72-char lines) |
| `commit_spelling` | Commit messages | Spell-check via codespell |

Features `--enable` and `--disable` flags, `.linter-ignore` file support, and TTY-aware colored output.

## Seed Job (Cache Warming)

The `build-seed` job pre-builds sstate caches for ~19 supported machines:

```
anacapa bletchley bletchley15 catalina clemente e3c246d4i
evb-npcm845 gb200nvl-obmc gbs harma minerva p10bmc romulus
santabarbara ventura ventura2 witherspoon yosemite4 yosemite5
```

This dramatically speeds up per-commit CI builds since BitBake reuses cached artifacts instead of building everything from scratch. If a build fails for one machine, it continues to the next.

## Docker Infrastructure

### Image Hierarchy

```
Ubuntu Base (public.ecr.aws/ubuntu)
├── Unit Test Image (openbmc/ubuntu-unit-test)
│   ├── 30+ pre-built OpenBMC packages
│   ├── Build tools (meson, cmake, autotools)
│   ├── Analysis tools (cppcheck, valgrind, clang-tidy)
│   └── Formatting tools (clang-format, black, shellcheck, etc.)
│
├── QEMU Robot Test Image (openbmc/ubuntu-robot-qemu)
│   ├── QEMU with ARM support
│   ├── Robot Framework + libraries
│   ├── Redfish tools (redfish, redfishtool)
│   ├── Firefox + geckodriver (Selenium tests)
│   └── ipmitool, sshpass, socat
│
├── BitBake Build Image (generated by build-setup.sh)
│   ├── Fedora or Ubuntu base
│   └── BitBake build environment
│
└── Rootfs Size Image (openbmc/ubuntu-rootfs-size)
    └── squashfs-tools, Python 3
```

### Caching and Cleanup

- **Tagging convention** — images use `YYYY-Www` (ISO week) tags combined with Dockerfile content hashes
- **Cleanup** — `scripts/clean-unit-test-docker` runs weekly to remove stale images
- **Cache invalidation** — changing the Dockerfile content hash forces a rebuild
- **Runtime support** — all scripts support both Docker and Podman

## Key Environment Variables

| Variable | Used By | Purpose |
|----------|---------|---------|
| `WORKSPACE` | All scripts | Jenkins workspace directory |
| `UNIT_TEST_PKG` | `run-unit-test-docker.sh` | Repository name to test |
| `GERRIT_PROJECT` | `userid-validation` | Gerrit project path |
| `GERRIT_BRANCH` | Multiple | Branch under review |
| `GERRIT_CHANGE_NUMBER` | `userid-validation` | Gerrit change number |
| `SSH_KEY` | `userid-validation` | Jenkins SSH key for Gerrit |
| `target` | `build-setup.sh` | Machine target for BitBake |
| `DOCKER_REG` | All Docker scripts | Docker registry override |
| `http_proxy` | All Docker scripts | Proxy configuration |
| `UPSTREAM_WORKSPACE` | `run-qemu-robot-test.sh` | Path to QEMU artifacts |
| `QEMU_RUN_TIMER` | `run-qemu-robot-test.sh` | QEMU runtime before shutdown |
| `INTERACTIVE` | `run-unit-test-docker.sh` | Drop to bash shell for debugging |

## References

- [Jenkins Instance](https://jenkins.openbmc.org/)
- [openbmc-build-scripts Repository](https://github.com/openbmc/openbmc-build-scripts)
- [CI Authorization Design Document](https://github.com/openbmc/docs/blob/master/designs/ci-authorization.md)
- [OpenBMC Contributing Guide](https://github.com/openbmc/docs/blob/master/CONTRIBUTING.md)
- [Gerrit Setup Guide](https://github.com/openbmc/docs/blob/master/development/gerrit-setup.md)
- [Adding a System to Hardware CI](https://github.com/openbmc/openbmc/wiki/Adding-a-System-to-Hardware-Continuous-Integration)
