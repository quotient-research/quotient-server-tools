# Quotient Server Tools

This repository contains the built Debian packages and APT repository for Quotient server automation tools.

## Licensing and activation

- **Install:** The public APT flow does **not** require a license key. You can `apt install` the Quotient server tools package without passing license parameters on the command line for a normal retail install.
- **End customers:** After purchase, enter your license key in the **Quotient mobile app** or the **Quotient server web UI** (Settings) to activate product entitlements. Do not publish keys in chat or email bodies when avoidable.
- **Authorized distributors / technicians:** Hardware may be installed and activated **before shipment** using your **internal runbook** (which may include command-line or scripted steps on the appliance). That path is for trained staff only, not for retail install docs.

Product tracking: [ecosystem#86](https://github.com/quotient-research/ecosystem/issues/86).

## Repository Structure

- `packages/` - Built .deb package files
- `docs/apt-repo/` - APT repository (served via GitHub Pages)
- `channels.json` - The version each APT channel (`dev`, `preview`, `stable`) carries

## Releases

Every package version is a [GitHub Release](https://github.com/quotient-research/quotient-server-tools/releases). Each one has the `.deb`, `bootstrap-repo.sh` and `SHA256SUMS`. Dev builds are prereleases. The **latest** release is always the current stable version, so this URL serves the stable bootstrap script:

```
https://github.com/quotient-research/quotient-server-tools/releases/latest/download/bootstrap-repo.sh
```

A published version never changes. Mainframes install from the signed APT repository below, which checks every package for them. To check a manual download, use `sha256sum -c SHA256SUMS`. CI creates and promotes releases ([ecosystem#273](https://github.com/quotient-research/ecosystem/issues/273), step 5c).

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
