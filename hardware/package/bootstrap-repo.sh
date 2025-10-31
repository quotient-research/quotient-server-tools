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
if curl -fsSL "$KEY_URL" -o /tmp/quotient-repo.gpg 2>/dev/null; then
    # Verify it's actually a GPG key
    if gpg --show-keys /tmp/quotient-repo.gpg >/dev/null 2>&1; then
        # Convert to binary format and install
        cat /tmp/quotient-repo.gpg | gpg --dearmor > /usr/share/keyrings/quotient.gpg 2>/dev/null
        chmod 644 /usr/share/keyrings/quotient.gpg
        rm -f /tmp/quotient-repo.gpg
        echo "✅ GPG key installed and verified"
        GPG_KEY_EXISTS=true
        
        # Show key info for verification
        KEY_INFO=$(gpg --show-keys /usr/share/keyrings/quotient.gpg 2>/dev/null | grep -A1 "^pub")
        if [ -n "$KEY_INFO" ]; then
            echo "   Key fingerprint:"
            echo "$KEY_INFO" | grep -v "^pub" | head -1 | sed 's/^/   /'
        fi
    else
        echo "⚠️  Downloaded file is not a valid GPG key"
        rm -f /tmp/quotient-repo.gpg
    fi
else
    echo "⚠️  GPG key not found at $KEY_URL"
    echo "   Repository will use trusted mode (less secure)"
fi

# Add repository to sources.list.d
echo "Adding repository to APT sources..."
if [ "$GPG_KEY_EXISTS" = true ]; then
    # Use signed repository (recommended - verifies package authenticity)
    REPO_LINE="deb [signed-by=/usr/share/keyrings/quotient.gpg] ${REPO_URL} stable main"
    echo "   Using GPG-signed repository (secure)"
else
    # Use unsigned repository with trusted flag (not recommended for production)
    REPO_LINE="deb [trusted=yes] ${REPO_URL} stable main"
    echo "⚠️  WARNING: Using unsigned repository (less secure)"
    echo "   Packages will NOT be verified for authenticity"
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

# Verify package is available before attempting installation
echo "Checking package availability..."
if apt-cache show quotient-server-tools >/dev/null 2>&1; then
    echo "✅ Package found in repository"
else
    echo "❌ Package not found in APT cache"
    echo ""
    echo "Debugging information:"
    echo "  Repository URL: ${REPO_URL}"
    echo "  Checking repository structure..."
    curl -sI "${REPO_URL}/dists/stable/Release" | head -3 || echo "  ⚠️  Cannot access Release file"
    echo ""
    echo "  Available packages from repository:"
    apt-cache search --names-only . | grep -i quotient || echo "  No packages found matching 'quotient'"
    echo ""
    echo "  Direct package list check:"
    curl -s "${REPO_URL}/dists/stable/main/binary-amd64/Packages" | grep "^Package:" | head -5 || echo "  Cannot read Packages file"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify repository is accessible: curl -I ${REPO_URL}/dists/stable/Release"
    echo "  2. Check package exists: curl ${REPO_URL}/dists/stable/main/binary-amd64/Packages | grep -A10 'quotient-server-tools'"
    echo "  3. Verify GitHub Pages is enabled: https://github.com/${GITHUB_ORG}/${REPO_NAME}/settings/pages"
    echo "  4. Try manual update: sudo apt-get update -o Acquire::Check-Valid-Until=false"
    exit 1
fi

# Install or upgrade quotient-server-tools
echo "Installing quotient-server-tools..."
INSTALL_OUTPUT=$(apt-get install -y quotient-server-tools 2>&1)
INSTALL_EXIT=$?

if [ $INSTALL_EXIT -ne 0 ]; then
    echo "⚠️  Package installation failed (exit code: $INSTALL_EXIT)"
    echo "$INSTALL_OUTPUT" | tail -10
    echo ""
    echo "Troubleshooting:"
    echo "  - Check full error output above"
    echo "  - Verify package dependencies are available"
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

