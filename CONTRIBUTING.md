# Contributing to OpenBMC Guide Tutorial

Thank you for your interest in contributing! This guide helps ensure consistency across all documentation.

## How to Contribute

1. **Fork the repository**
2. **Create a branch** for your changes
3. **Make your changes** following the guidelines below
4. **Test locally** with `bundle exec jekyll serve`
5. **Submit a pull request**

## Guide Structure

Every guide should follow this template:

```markdown
---
layout: default
title: <Guide Title>
parent: <Section Name>
nav_order: <number>
difficulty: beginner|intermediate|advanced
prerequisites:
  - <prerequisite-guide-1>
  - <prerequisite-guide-2>
---

# <Guide Title>

## Overview

Brief introduction (2-3 paragraphs):
- What this component/feature does
- Why it matters
- When you would use it

## Architecture

- Component diagram (ASCII or image)
- Key interfaces and D-Bus paths
- Data flow explanation

## Configuration

### Required Files

| File | Location | Purpose |
|------|----------|---------|
| ... | ... | ... |

### Configuration Example

\`\`\`json
{
  "example": "configuration"
}
\`\`\`

## Porting Guide

Step-by-step instructions:

1. **Prerequisites**: What must be in place first
2. **Configuration**: Files to create/modify
3. **Recipe changes**: Bitbake/Yocto modifications
4. **Verification**: How to test it works

## Code Examples

Link to examples in the `examples/` directory.

## Troubleshooting

### Common Issue 1

**Symptom**: Description of what goes wrong
**Cause**: Why it happens
**Solution**: How to fix it

## References

- [Official Repo](https://github.com/openbmc/...)
- [D-Bus Interfaces](https://github.com/openbmc/phosphor-dbus-interfaces/...)
- Related guides: [Guide 1](link), [Guide 2](link)
```

## Style Guidelines

### Writing

- Use **active voice**: "Configure the sensor" not "The sensor should be configured"
- Use **present tense**: "This creates a file" not "This will create a file"
- Be **concise**: Avoid unnecessary words
- Use **you/your**: Address the reader directly

### Code

- All code examples must be **tested on QEMU romulus**
- Include the **OpenBMC commit** or version tested against
- Use **syntax highlighting** with the correct language tag
- Keep examples **minimal but complete**

### Formatting

- Use **headers** (##, ###) to organize content
- Use **callouts** for warnings, notes, and tips:
  ```markdown
  {: .warning }
  This action cannot be undone.

  {: .note }
  This is optional but recommended.

  {: .tip }
  Here's a helpful shortcut.
  ```
- Use **tables** for structured data
- Use **bullet lists** for unordered items
- Use **numbered lists** for sequential steps

### Links

- Use **relative links** for internal pages: `[Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %})`
- Use **absolute links** for external resources
- Prefer **GitHub permalinks** (with commit hash) for OpenBMC source references

## Adding Examples

1. Create a directory under `examples/<category>/`
2. Include:
   - Complete, buildable source code
   - `README.md` with build/test instructions
   - `meson.build` or build configuration
3. Test on QEMU before submitting

## Testing Changes Locally

```bash
# Install dependencies
bundle install

# Serve locally with live reload
bundle exec jekyll serve --livereload

# Build without serving
bundle exec jekyll build
```

Visit `http://localhost:4000/openbmc-guide-tutorial/` to preview.

## Review Checklist

Before submitting a PR, verify:

- [ ] Follows the guide template structure
- [ ] Code examples are tested on QEMU
- [ ] All links work (internal and external)
- [ ] Spelling and grammar are correct
- [ ] Difficulty and prerequisites are set
- [ ] Related guides are cross-referenced

## Questions?

Open an issue for questions about contributing.
