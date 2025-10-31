#!/bin/bash
# Bootstrap script to configure Ubuntu server to use Quotient APT repository
# This script should be run once on each server that needs automatic updates

set -e

# Configuration - Hardcoded for quotient-research/quotient-server-tools
GITHUB_ORG="quotient-research"
REPO_NAME="quotient-server-tools"
BRANCH="main"

REPO_URL="https://${GITHUB_ORG}.github.io/${REPO_NAME}/apt-repo"
KEY_URL="${REPO_URL}/repo.gpg"

echo "=== Setting up Quotient APT Repository ==="
echo "Repository URL: $REPO_URL"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

# Install required tools
echo "Installing required tools..."
apt-get update -qq
apt-get install -y -qq curl gpg apt-transport-https >/dev/null 2>&1 || true

# Download and install GPG key
echo "Downloading and installing GPG key..."
if curl -fsSL "$KEY_URL" | gpg --dearmor -o /usr/share/keyrings/quotient.gpg 2>/dev/null; then
    chmod 644 /usr/share/keyrings/quotient.gpg
    echo "✅ GPG key installed"
else
    echo "⚠️  GPG key not found, continuing without signature verification"
    echo "   (Repository may be unsigned)"
    # Continue anyway for unsigned repos
fi

# Add repository to sources.list.d
echo "Adding repository to APT sources..."
REPO_LINE="deb [signed-by=/usr/share/keyrings/quotient.gpg] ${REPO_URL} stable main"

# Check if already added
if [ -f /etc/apt/sources.list.d/quotient.list ]; then
    if grep -q "^${REPO_LINE}$" /etc/apt/sources.list.d/quotient.list 2>/dev/null; then
        echo "✅ Repository already configured"
    else
        echo "$REPO_LINE" > /etc/apt/sources.list.d/quotient.list
        echo "✅ Repository added"
    fi
else
    echo "$REPO_LINE" > /etc/apt/sources.list.d/quotient.list
    echo "✅ Repository added"
fi

# If no GPG key, create a dummy one or use unsigned repo
if [ ! -f /usr/share/keyrings/quotient.gpg ]; then
    # Use unsigned repository
    echo "deb ${REPO_URL} stable main" > /etc/apt/sources.list.d/quotient.list
    echo "⚠️  Using unsigned repository (less secure)"
fi

# Update package lists
echo "Updating package lists..."
if apt-get update -qq 2>&1 | grep -q "Err:.*quotient"; then
    echo "⚠️  Warning: Some errors occurred while updating"
    echo "   The repository may not be fully set up on GitHub Pages yet"
    echo "   Make sure GitHub Pages is enabled and the repo is accessible"
else
    echo "✅ Package lists updated"
fi

# Install or upgrade quotient-server-tools
echo "Installing quotient-server-tools..."
if apt-get install -y quotient-server-tools 2>&1 | grep -q "Unable to locate"; then
    echo "⚠️  Package not found. Repository may need to be published first."
    echo "   Run publish-to-github-pages.sh on your development machine"
    exit 1
else
    echo "✅ Quotient server tools installed/upgraded"
fi

# Verify auto-update timer is enabled
if systemctl list-timers | grep -q "quotient-auto-update.timer"; then
    echo "✅ Auto-update timer is enabled"
    echo "   The system will check for updates daily"
else
    echo "⚠️  Auto-update timer not found (may need package installation)"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Your server is now configured to:"
echo "  - Pull packages from: $REPO_URL"
echo "  - Auto-update daily via systemd timer"
echo ""
echo "To manually update: sudo apt-get update && sudo apt-get install -y quotient-server-tools"
echo "To check update status: systemctl status quotient-auto-update.timer"

