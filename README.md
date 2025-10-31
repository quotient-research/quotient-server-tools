# Quotient Server Tools

This repository contains the built Debian packages and APT repository for Quotient server automation tools.

## Repository Structure

- `packages/` - Built .deb package files
- `docs/apt-repo/` - APT repository (served via GitHub Pages)

## Usage

See the [main Quotient repository](https://github.com/code-exitos/quotient-api) for source code and build instructions.

## Bootstrap Servers

On Ubuntu servers:

```bash
curl -fsSL https://raw.githubusercontent.com/quotient-research/quotient-server-tools/main/hardware/package/bootstrap-repo.sh | sudo bash
```

## APT Repository

The APT repository is available at:
```
https://quotient-research.github.io/quotient-server-tools/apt-repo/
```

This repository is automatically updated when packages are built and published from the main Quotient repository.
