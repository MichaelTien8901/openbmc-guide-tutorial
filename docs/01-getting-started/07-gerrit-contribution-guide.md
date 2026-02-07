---
layout: default
title: Gerrit Contribution Guide
parent: Getting Started
nav_order: 7
difficulty: beginner
prerequisites:
  - environment-setup
  - first-build
last_modified_date: 2026-02-06
---

# Gerrit Contribution Guide
{: .no_toc }

Submit your first patch to the OpenBMC project using Gerrit code review.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

OpenBMC uses [Gerrit](https://gerrit.openbmc.org/) for code review, not GitHub pull requests. Every change to the OpenBMC codebase goes through Gerrit review before it merges into the upstream repository.

This guide walks you through the entire contribution workflow: account creation, SSH setup, commit conventions, patch submission, reviewer feedback, CI validation, and the upstream-first kernel policy.

**Key concepts covered:**
- Creating a Gerrit account and configuring SSH access
- Installing the commit-msg hook for Change-Id generation
- Submitting patches with `git push origin HEAD:refs/for/master`
- Updating patches with `git commit --amend`
- Understanding Jenkins CI results and common failures
- OpenBMC's upstream-first kernel policy

---

## Prerequisites

Before starting this guide, make sure you have:

- [ ] A working OpenBMC build environment ([Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}))
- [ ] A completed first build of `obmc-phosphor-image` ([First Build]({% link docs/01-getting-started/03-first-build.md %}))
- [ ] A GitHub account (used for Gerrit authentication)
- [ ] Git installed and configured with your name and email

{: .note }
OpenBMC Gerrit uses your GitHub account for authentication. You do not need to create a separate Gerrit account.

---

## Step 1: Create Your Gerrit Account

### Sign In and Configure

1. Open [https://gerrit.openbmc.org/](https://gerrit.openbmc.org/) and click **Sign In**.
2. Select **GitHub** as the authentication provider and authorize the application.
3. In Gerrit **Settings**, verify your display name and email under **Profile** and **Email Addresses**.

Verify your local git configuration matches your Gerrit email:

```bash
git config --global user.name "Your Full Name"
git config --global user.email "your-email@example.com"
```

{: .warning }
Your git `user.email` must match the email registered in Gerrit. Mismatched emails cause a "committer email does not match" rejection on push.

### Sign the Contributor License Agreement (CLA)

OpenBMC requires a signed CLA before you can submit patches:

1. In Gerrit Settings, go to **Agreements**.
2. Click **New Contributor Agreement**, select individual or corporate, and sign it.

{: .note }
If you contribute on behalf of your employer, check whether your company has already signed a corporate CLA. Contact the [OpenBMC mailing list](https://lists.ozlabs.org/listinfo/openbmc) if you are unsure.

---

## Step 2: Configure SSH Access

Gerrit uses SSH for git push and pull operations. Generate an SSH key pair and register the public key with Gerrit.

### Generate and Register Your Key

```bash
# Generate an SSH key (skip if you already have one)
ssh-keygen -t ed25519 -C "your-email@example.com" -f ~/.ssh/id_openbmc
```

Copy the public key and add it in Gerrit under **Settings** > **SSH Keys**:

```bash
cat ~/.ssh/id_openbmc.pub
```

### Configure SSH for Gerrit

Add a host entry to `~/.ssh/config` (create the file if it does not exist):

```bash
Host gerrit.openbmc.org
    User your-gerrit-username
    IdentityFile ~/.ssh/id_openbmc
    Port 29418
```

Replace `your-gerrit-username` with your Gerrit username from Settings > Profile.

### Verify Connectivity

```bash
ssh -p 29418 gerrit.openbmc.org
```

A successful connection displays a "Welcome to Gerrit Code Review" banner.

{: .tip }
If you see "Permission denied (publickey)", verify that your SSH config points to the correct key file and that the public key is registered in Gerrit.

---

## Step 3: Install the commit-msg Hook

Gerrit tracks patches using a unique `Change-Id` in each commit message. The `commit-msg` hook generates this identifier automatically on every `git commit`.

### Clone and Install the Hook

```bash
# Clone the repository (example: phosphor-logging)
git clone ssh://gerrit.openbmc.org:29418/openbmc/phosphor-logging
cd phosphor-logging

# Install the commit-msg hook
scp -p -P 29418 gerrit.openbmc.org:hooks/commit-msg .git/hooks/
chmod +x .git/hooks/commit-msg
```

### Verify the Hook

```bash
echo "" >> README.md
git add README.md
git commit -m "Test commit-msg hook"
git log -1
```

You should see a `Change-Id:` line appended to the commit message. After verifying, reset the test:

```bash
git reset HEAD~1
git checkout -- README.md
```

{: .warning }
If the `Change-Id` line is missing, the hook is not installed correctly. Repeat the `scp` command above. Without a Change-Id, Gerrit rejects your push.

### Add the Hook to an Existing Clone

If you already cloned from GitHub, add the Gerrit remote and hook:

```bash
git remote add gerrit ssh://gerrit.openbmc.org:29418/openbmc/<repo-name>
scp -p -P 29418 gerrit.openbmc.org:hooks/commit-msg .git/hooks/
chmod +x .git/hooks/commit-msg
```

---

## Step 4: Submit a Patch

### Create a Topic Branch

Always work on a topic branch, never directly on `master`:

```bash
git checkout master
git pull origin master
git checkout -b fix-typo-in-readme
```

### Commit with Sign-off

OpenBMC requires a `Signed-off-by` line in every commit (Developer Certificate of Origin). Use the `-s` flag:

```bash
git add README.md
git commit -s
```

Write your commit message following this format:

```
component: Short summary (50 chars or less)

Longer description explaining what you changed and why. Wrap at
72 characters. Focus on motivation, not mechanics.

Signed-off-by: Your Name <your-email@example.com>
Change-Id: Iabc123... (auto-generated by the hook)
```

{: .tip }
The `-s` flag adds the `Signed-off-by` line automatically from your git config. You do not need to type it manually.

### Commit Message Guidelines

| Rule | Example |
|------|---------|
| Start with component name and colon | `phosphor-logging: Fix memory leak` |
| Subject line under 50 characters | Short and descriptive |
| Imperative mood in subject | "Fix bug" not "Fixed bug" |
| Blank line after subject | Separates subject from body |
| Body wrapped at 72 characters | Readable in terminal and Gerrit |
| Explain *why*, not just *what* | The diff shows what changed |
| Include `Signed-off-by` (use `-s`) | Required for all patches |
| Keep the `Change-Id` line | Required for Gerrit tracking |

### Push to Gerrit

Push your commit using the special `refs/for/master` reference:

```bash
git push origin HEAD:refs/for/master
```

{: .warning }
Do **not** push to `refs/heads/master`. That attempts a direct push to master and is rejected. Always use `refs/for/master` to create a review.

A successful push shows a URL to your new review:

```
remote:   https://gerrit.openbmc.org/c/openbmc/phosphor-logging/+/12345 component: Short summary [NEW]
```

You can group related patches with a topic:

```bash
git push origin HEAD:refs/for/master%topic=fix-memory-leak
```

---

## Step 5: Update a Patch After Review

Reviewers may request changes. To update your patch, amend the existing commit and push again -- do not create a new commit.

```bash
# Make the requested changes
vi README.md
git add README.md

# Amend the existing commit (keeps the same Change-Id)
git commit --amend

# Push the updated patch
git push origin HEAD:refs/for/master
```

Gerrit detects the same `Change-Id` and creates a new **patch set** on the existing review.

{: .warning }
Do not create a new commit for review updates. A new commit generates a new Change-Id and creates a separate review instead of updating the existing one.

### Rebase on Latest Master

If your patch falls behind master, rebase before pushing:

```bash
git fetch origin
git rebase origin/master
# Resolve any conflicts, then:
git rebase --continue
git push origin HEAD:refs/for/master
```

{: .note }
Rebasing preserves the `Change-Id`. Gerrit correctly associates the rebased commit with the original review.

---

## Step 6: Understand CI Integration

Every patch pushed to Gerrit triggers a Jenkins CI build. Jenkins compiles the code, runs tests, and reports results on the review.

### Jenkins Results

| Label | Meaning |
|-------|---------|
| **Verified +1** | Build and tests passed |
| **Verified -1** | Build or tests failed |

Jenkins must report `Verified +1` before your patch can merge. A human reviewer must also approve with `Code-Review +2`. Click the build URL in the Jenkins comment to see full console output.

### Common CI Failure Reasons

**Compilation error**: Fix errors locally with `devtool build <recipe>`, amend, and push again.

**Unit test failure**: Reproduce locally by building and checking test output. Fix the failing test before pushing.

**Formatting failure**: OpenBMC enforces `clang-format` for C/C++. Format your code before committing:

```bash
clang-format -i path/to/your/file.cpp
```

**Merge conflict**: Rebase on latest master, resolve conflicts, and push.

{: .tip }
Always build and test locally before pushing to Gerrit. This saves CI resources and reduces turnaround time.

---

## Step 7: Understand the Upstream-First Kernel Policy

OpenBMC follows a strict **upstream-first** policy for Linux kernel changes. Any kernel modification must first be submitted to the upstream Linux kernel (kernel.org) before it can be accepted into OpenBMC.

### Why Upstream-First Matters

- **Long-term maintenance**: Upstream patches are maintained by the Linux kernel community.
- **Quality assurance**: The upstream review process catches bugs early.
- **Broad compatibility**: Upstream drivers work across all platforms.
- **License compliance**: Keeps the OpenBMC kernel tree clean.

### What Requires Upstream Submission

| Change Type | Upstream Required? | Example |
|-------------|-------------------|---------|
| New device driver | Yes | ASPEED ADC driver |
| Device tree binding | Yes | New sensor node |
| Bug fix in existing driver | Yes | I2C timeout fix |
| Board device tree (.dts) | Yes (new SoC/board) | aspeed-bmc-vendor-board.dts |
| Kernel config change | No | Enable/disable CONFIG option |
| Backport of accepted patch | No | Cherry-pick from mainline |

### Referencing Upstream Commits

When backporting an upstream kernel patch, reference the commit in your message:

```
ARM: dts: aspeed: Add sensor nodes for new platform

Backport upstream commit abc123def456 from Linux 6.x to the
OpenBMC kernel tree.

Upstream: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=abc123def456
Signed-off-by: Your Name <your-email@example.com>
Change-Id: I...
```

{: .note }
If your change does not touch upstream kernel code (for example, a Yocto recipe change), the upstream-first policy does not apply.

---

## Quick Reference

| Task | Command |
|------|---------|
| Clone from Gerrit | `git clone ssh://gerrit.openbmc.org:29418/openbmc/<repo>` |
| Install commit-msg hook | `scp -p -P 29418 gerrit.openbmc.org:hooks/commit-msg .git/hooks/` |
| Submit new patch | `git push origin HEAD:refs/for/master` |
| Submit with topic | `git push origin HEAD:refs/for/master%topic=my-topic` |
| Update existing patch | `git commit --amend && git push origin HEAD:refs/for/master` |
| Check SSH access | `ssh -p 29418 gerrit.openbmc.org` |
| Query your open patches | `ssh -p 29418 gerrit.openbmc.org gerrit query owner:self status:open` |
| Download a patch locally | `git fetch origin refs/changes/45/12345/1 && git checkout FETCH_HEAD` |

---

## Troubleshooting

### Issue: Push rejected with "missing Change-Id"

**Symptom**: `git push` fails with "missing Change-Id in message footer".

**Cause**: The `commit-msg` hook is not installed.

**Solution**: Install the hook, then amend the commit to trigger it:
```bash
scp -p -P 29418 gerrit.openbmc.org:hooks/commit-msg .git/hooks/
chmod +x .git/hooks/commit-msg
git commit --amend --no-edit
git push origin HEAD:refs/for/master
```

### Issue: Push rejected with "committer email does not match"

**Cause**: Your git `user.email` differs from Gerrit.

**Solution**: Update your email and amend:
```bash
git config --global user.email "your-gerrit-email@example.com"
git commit --amend --reset-author --no-edit
git push origin HEAD:refs/for/master
```

### Issue: Push rejected with "not permitted"

**Cause**: Pushing to `refs/heads/master` instead of `refs/for/master`, or CLA not signed.

**Solution**: Use the correct reference and sign the CLA in Gerrit Settings > Agreements:
```bash
git push origin HEAD:refs/for/master
```

### Issue: SSH connection times out

**Cause**: Firewall blocking port 29418.

**Solution**: Test with `nc -zv gerrit.openbmc.org 29418`. If blocked, ask your network administrator to allow outbound TCP on port 29418.

### Issue: Gerrit shows "Cannot merge"

**Cause**: A conflicting patch was merged while your review was pending.

**Solution**: Rebase and push:
```bash
git fetch origin && git rebase origin/master
# Resolve conflicts, then:
git rebase --continue
git push origin HEAD:refs/for/master
```

---

## References

### Official Resources
- [OpenBMC Gerrit](https://gerrit.openbmc.org/) - Code review platform
- [OpenBMC Contributing Guide](https://github.com/openbmc/docs/blob/master/CONTRIBUTING.md) - Official contribution guidelines
- [Gerrit User Guide](https://gerrit-review.googlesource.com/Documentation/intro-user.html) - Gerrit documentation

### Related Guides
- [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %}) - Development environment
- [Development Workflow]({% link docs/01-getting-started/04-development-workflow.md %}) - Iterate with devtool
- [Devtool Workflow Guide]({% link docs/01-getting-started/06-devtool-workflow-guide.md %}) - Modify-build-deploy cycle

### Community
- [OpenBMC Mailing List](https://lists.ozlabs.org/listinfo/openbmc) - Discussion and questions
- [OpenBMC Discord](https://discord.gg/openbmc) - Real-time chat

---

{: .note }
**Tested on**: Ubuntu 22.04, OpenBMC master branch (Kirkstone/Scarthgap), Gerrit 3.x
Last updated: 2026-02-06
