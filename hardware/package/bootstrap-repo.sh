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
GPG_KEY_EXISTS=false
if curl -fsSL "$KEY_URL" | gpg --dearmor -o /usr/share/keyrings/quotient.gpg 2>/dev/null; then
    chmod 644 /usr/share/keyrings/quotient.gpg
    echo "✅ GPG key installed"
    GPG_KEY_EXISTS=true
else
    echo "⚠️  GPG key not found, continuing without signature verification"
    echo "   (Repository may be unsigned)"
    # Continue anyway for unsigned repos
fi

# Add repository to sources.list.d
echo "Adding repository to APT sources..."
if [ "$GPG_KEY_EXISTS" = true ]; then
    # Use signed repository
    REPO_LINE="deb [signed-by=/usr/share/keyrings/quotient.gpg] ${REPO_URL} stable main"
else
    # Use unsigned repository with trusted flag
    REPO_LINE="deb [trusted=yes] ${REPO_URL} stable main"
    echo "⚠️  Using unsigned repository (less secure but required)"
fi

# Check if already added
if [ -f /etc/apt/sources.list.d/quotient.list ]; then
    if grep -q "^deb.*${REPO_URL}.*stable main" /etc/apt/sources.list.d/quotient.list 2>/dev/null; then
        # Update if different (e.g., switching from signed to unsigned or vice versa)
        echo "$REPO_LINE" > /etc/apt/sources.list.d/quotient.list
        echo "✅ Repository updated"
    else
        echo "✅ Repository already configured"
    fi
else
    echo "$REPO_LINE" > /etc/apt/sources.list.d/quotient.list
    echo "✅ Repository added"
fi

# Update package lists
echo "Updating package lists..."
UPDATE_OUTPUT=$(apt-get update -qq 2>&1)
UPDATE_EXIT=$?

if [ $UPDATE_EXIT -ne 0 ] || echo "$UPDATE_OUTPUT" | grep -qi "Err:.*quotient\|404\|not found"; then
    echo "⚠️  Warning: Some errors occurred while updating"
    echo "$UPDATE_OUTPUT" | grep -i "quotient\|Err:\|404" | head -3 || true
    echo ""
    echo "Troubleshooting:"
    echo "  - Verify GitHub Pages is enabled at: https://github.com/${GITHUB_ORG}/${REPO_NAME}/settings/pages"
    echo "  - Check repository is accessible: curl -I ${REPO_URL}/dists/stable/Release"
    echo "  - Repository URL: ${REPO_URL}"
    exit 1
else
    echo "✅ Package lists updated"
fi

# Install or upgrade quotient-server-tools
echo "Installing quotient-server-tools..."
INSTALL_OUTPUT=$(apt-get install -y quotient-server-tools 2>&1)
INSTALL_EXIT=$?

if [ $INSTALL_EXIT -ne 0 ] || echo "$INSTALL_OUTPUT" | grep -qi "Unable to locate\|Package.*not found\|E: Unable to locate"; then
    echo "⚠️  Package installation failed"
    echo "$INSTALL_OUTPUT" | grep -i "unable\|not found\|error" | head -3 || echo "$INSTALL_OUTPUT" | tail -5
    echo ""
    echo "Troubleshooting:"
    echo "  - Verify package exists: curl ${REPO_URL}/dists/stable/main/binary-amd64/Packages | grep -A5 'quotient-server-tools'"
    echo "  - Check repository structure is correct"
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

