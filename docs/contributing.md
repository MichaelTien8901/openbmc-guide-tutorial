---
layout: default
title: Contributing
nav_order: 99
description: "How to contribute to the OpenBMC Guide Tutorial documentation"
permalink: /contributing/
---

# Contributing to OpenBMC Guide Tutorial

Thank you for your interest in contributing! This guide ensures consistency across all documentation.

## Quick Start

1. **Fork** the repository on GitHub
2. **Clone** your fork locally
3. **Create a branch** for your changes
4. **Make your changes** following the guidelines below
5. **Test locally** with `bundle exec jekyll serve`
6. **Submit a pull request**

## Ways to Contribute

### Report Issues

Found an error or missing information? [Open an issue](https://github.com/MichaelTien8901/openbmc-guide-tutorial/issues) with:
- Clear description of the problem
- Link to the affected page
- Suggested fix (if you have one)

### Improve Existing Guides

- Fix typos, broken links, or outdated information
- Add missing configuration examples
- Improve code samples with better explanations
- Update for newer OpenBMC versions

### Add New Content

- Write guides for undocumented features
- Add troubleshooting sections
- Create new code examples
- Expand porting documentation for different platforms

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

- Component diagram (Mermaid or ASCII)
- Key interfaces and D-Bus paths
- Data flow explanation

## Configuration

### Required Files

| File | Location | Purpose |
|------|----------|---------|
| ... | ... | ... |

### Configuration Example

```json
{
  "example": "configuration"
}
```

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

| Do | Don't |
|----|-------|
| Use **active voice**: "Configure the sensor" | "The sensor should be configured" |
| Use **present tense**: "This creates a file" | "This will create a file" |
| Be **concise**: Avoid unnecessary words | Use filler phrases |
| Use **you/your**: Address the reader directly | Use passive constructions |

### Code Examples

{: .important }
All code examples must be tested on QEMU ast2600-evb or romulus before submitting.

- Include the OpenBMC commit hash or version tested against
- Use syntax highlighting with the correct language tag
- Keep examples minimal but complete
- Ensure examples are copy-paste ready

### Formatting

Use **callouts** for important information:

```markdown
{: .warning }
This action cannot be undone.

{: .note }
This is optional but recommended.

{: .tip }
Here's a helpful shortcut.
```

Use **tables** for structured data and **numbered lists** for sequential steps.

### Links

- **Internal links**: Use Jekyll's link tag
  ```markdown
  [Environment Setup]({% link docs/01-getting-started/02-environment-setup.md %})
  ```
- **External links**: Use absolute URLs
- **OpenBMC source**: Prefer GitHub permalinks with commit hash

## Adding Code Examples

1. Create a directory under `examples/<category>/`
2. Include:
   - Complete, buildable source code
   - `README.md` with build/test instructions
   - `meson.build` or appropriate build configuration
3. Test on QEMU before submitting

### Example Directory Structure

```
examples/
├── sensors/
│   ├── README.md
│   ├── meson.build
│   └── custom_sensor.cpp
├── dbus/
│   └── ...
```

## Testing Changes Locally

```bash
# Install dependencies (first time only)
bundle install

# Serve locally with live reload
bundle exec jekyll serve --livereload

# Build without serving
bundle exec jekyll build
```

Visit `http://localhost:4000/openbmc-guide-tutorial/` to preview your changes.

### Docker Alternative

```bash
docker run --rm -it -v "$PWD:/srv/jekyll" -p 4000:4000 \
  jekyll/jekyll:4.3 jekyll serve --host 0.0.0.0
```

## Pull Request Checklist

Before submitting, verify:

- [ ] Content follows the guide template structure
- [ ] Code examples are tested on QEMU
- [ ] All links work (internal and external)
- [ ] Spelling and grammar are correct
- [ ] Difficulty and prerequisites are set appropriately
- [ ] Related guides are cross-referenced
- [ ] Mermaid diagrams render correctly (if used)

## Commit Messages

Use clear, descriptive commit messages:

```
Add fan control troubleshooting section

- Document common PID tuning issues
- Add thermal runaway debugging steps
- Include dbus-monitor examples
```

## Review Process

1. Submit your pull request
2. Maintainers review for accuracy and style
3. Address any feedback
4. Once approved, changes are merged and auto-deployed

## Questions?

- [Open an issue](https://github.com/MichaelTien8901/openbmc-guide-tutorial/issues) for questions about contributing
- Check existing issues for common questions
- Reference the [OpenBMC docs](https://github.com/openbmc/docs) for authoritative information

---

{: .note }
This is a community project. All contributions are welcome, from fixing typos to adding complete guides. Every improvement helps the OpenBMC community.
