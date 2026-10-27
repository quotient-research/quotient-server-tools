#!/bin/bash
# Bootstrap script to configure Ubuntu server to use Quotient APT repository
# This script should be run once on each server that needs automatic updates
#
# Usage:
#   curl -fsSL https://...bootstrap-repo.sh | sudo bash                               # stable (default)
#   curl -fsSL https://...bootstrap-repo.sh | sudo QUOTIENT_CHANNEL=dev bash          # dev channel
#   curl -fsSL https://...bootstrap-repo.sh | sudo QUOTIENT_INSTALL_HTTP_PORT=9191 bash
#
# Supported channels: dev, preview, stable
#
# Install settings (ecosystem #287, #273), written to /etc/quotient/install.conf
# before the package installs. There is one install mode; these are the only
# choices:
#   QUOTIENT_INSTALL_HTTP_PORT=auto|80|9191-32767
#   QUOTIENT_INSTALL_SAMBA=off|include   (off by default; include installs Samba
#                                         first if it is missing)
#   QUOTIENT_INSTALL_FIREWALL=auto|off
#   QUOTIENT_INSTALL_AUTO_UPDATE=on|off
#   QUOTIENT_INSTALL_DESKTOP_SHORTCUT=on|off  (on by default: on a computer with
#                                         a desktop, a Quotient launcher on the
#                                         desktop and in the app menu of the
#                                         user running sudo)
# Quotient never changes SSH or the computer name, never turns a firewall on,
# and never installs Docker. Change the settings later with: sudo quotient configure

set -e

# Configuration - Hardcoded for quotient-research/quotient-server-tools
GITHUB_ORG="quotient-research"
REPO_NAME="quotient-server-tools"
BRANCH="main"

# Channel selection: defaults to stable for production
CHANNEL="${QUOTIENT_CHANNEL:-stable}"

# Validate channel
case "$CHANNEL" in
    dev|preview|stable) ;;
    *)
        echo "❌ Invalid channel: $CHANNEL (must be dev, preview, or stable)"
        exit 1
        ;;
esac

# Validate install settings before touching the system. The package's
# install-profile.sh validates again; this only fails fast on typos.
INSTALL_CONF="/etc/quotient/install.conf"
INSTALL_SETTINGS=""
for KEY in http_port samba firewall auto_update desktop_shortcut; do
    VAR="QUOTIENT_INSTALL_$(echo "$KEY" | tr '[:lower:]' '[:upper:]')"
    VALUE="${!VAR:-}"
    [ -n "$VALUE" ] || continue
    case "$KEY=$VALUE" in
        http_port=auto|samba=include|samba=off|firewall=auto|firewall=off|auto_update=on|auto_update=off|desktop_shortcut=on|desktop_shortcut=off) ;;
        http_port=*)
            # 80 is the ingress host port; any other port is a NodePort (9191-32767).
            if ! echo "$VALUE" | grep -Eq '^[1-9][0-9]{1,4}$' || \
               { [ "$VALUE" != 80 ] && { [ "$VALUE" -lt 9191 ] || [ "$VALUE" -gt 32767 ]; }; }; then
                echo "❌ Invalid $VAR=$VALUE (auto, 80, or a port from 9191 to 32767)"; exit 1
            fi ;;
        samba=*) echo "❌ Invalid $VAR=$VALUE (include or off)"; exit 1 ;;
        firewall=*) echo "❌ Invalid $VAR=$VALUE (auto or off)"; exit 1 ;;
        *) echo "❌ Invalid $VAR=$VALUE (on or off)"; exit 1 ;;
    esac
    INSTALL_SETTINGS="$INSTALL_SETTINGS $KEY=$VALUE"
done
# Install profiles and the settings that went with them were removed (#273).
for KEY in PROFILE HOSTNAME BLUETOOTH DOCKER SSH; do
    VAR="QUOTIENT_INSTALL_$KEY"
    if [ -n "${!VAR:-}" ]; then
        echo "ℹ️  $VAR is no longer used (there is one install mode); ignoring it"
    fi
done

REPO_URL="https://${GITHUB_ORG}.github.io/${REPO_NAME}/apt-repo"
KEY_URL="${REPO_URL}/repo.gpg"

echo "=== Setting up Quotient APT Repository ==="
echo "Repository URL: $REPO_URL"
echo "Channel: $CHANNEL"
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

# Download the repository signing key and check it is the one we publish
# (ecosystem #273). There is no unsigned fallback: a key that fails the check
# stops the install instead of trusting the repository blindly.
# Update QUOTIENT_REPO_KEY_FINGERPRINT when the signing key is rotated.
QUOTIENT_REPO_KEY_FINGERPRINT="AE772CBCB3BC29B247A794256781AAC9BFEA7E51"
echo "Downloading and verifying the repository signing key..."
KEY_TMP=$(mktemp)
if ! curl -fsSL "$KEY_URL" -o "$KEY_TMP"; then
    echo "❌ Could not download the repository signing key from $KEY_URL"
    rm -f "$KEY_TMP"; exit 1
fi
KEY_FPR=$(gpg --show-keys --with-colons "$KEY_TMP" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')
if [ "$KEY_FPR" != "$QUOTIENT_REPO_KEY_FINGERPRINT" ]; then
    echo "❌ The repository signing key does not match the expected fingerprint"
    echo "   expected: $QUOTIENT_REPO_KEY_FINGERPRINT"
    echo "   got:      ${KEY_FPR:-not a valid key}"
    rm -f "$KEY_TMP"; exit 1
fi
gpg --dearmor < "$KEY_TMP" > /usr/share/keyrings/quotient.gpg
chmod 644 /usr/share/keyrings/quotient.gpg
rm -f "$KEY_TMP"
echo "✅ Signing key verified ($KEY_FPR)"

# Add repository to sources.list.d
echo "Adding repository to APT sources..."
REPO_LINE="deb [signed-by=/usr/share/keyrings/quotient.gpg] ${REPO_URL} ${CHANNEL} main"

# Check if already added (always update to ensure correct channel)
if [ -f /etc/apt/sources.list.d/quotient.list ]; then
    echo "$REPO_LINE" > /etc/apt/sources.list.d/quotient.list
    echo "✅ Repository updated (channel: ${CHANNEL})"
else
    echo "$REPO_LINE" > /etc/apt/sources.list.d/quotient.list
    echo "✅ Repository added (channel: ${CHANNEL})"
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
    echo "  - Check repository is accessible: curl -I ${REPO_URL}/dists/${CHANNEL}/Release"
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
    echo "  Channel: ${CHANNEL}"
    echo "  Checking repository structure..."
    curl -sI "${REPO_URL}/dists/${CHANNEL}/Release" | head -3 || echo "  ⚠️  Cannot access Release file"
    echo ""
    echo "  Available packages from repository:"
    apt-cache search --names-only . | grep -i quotient || echo "  No packages found matching 'quotient'"
    echo ""
    echo "  Direct package list check:"
    curl -s "${REPO_URL}/dists/${CHANNEL}/main/binary-amd64/Packages" | grep "^Package:" | head -5 || echo "  Cannot read Packages file"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify repository is accessible: curl -I ${REPO_URL}/dists/${CHANNEL}/Release"
    echo "  2. Check package exists: curl ${REPO_URL}/dists/${CHANNEL}/main/binary-amd64/Packages | grep -A10 'quotient-server-tools'"
    echo "  3. Verify GitHub Pages is enabled: https://github.com/${GITHUB_ORG}/${REPO_NAME}/settings/pages"
    echo "  4. Try manual update: sudo apt-get update -o Acquire::Check-Valid-Until=false"
    exit 1
fi

# Write install settings where postinst and first-boot configure read them.
if [ -n "$INSTALL_SETTINGS" ]; then
    mkdir -p /etc/quotient
    touch "$INSTALL_CONF"
    for SETTING in $INSTALL_SETTINGS; do
        KEY="${SETTING%%=*}"
        awk -v k="$KEY" -v v="${SETTING#*=}" '
            !done && $0 ~ "^[[:space:]]*#?[[:space:]]*" k "[[:space:]]*=" { print k "=" v; done=1; next }
            $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { next }
            { print }
            END { if (!done) print k "=" v }
        ' "$INSTALL_CONF" > "$INSTALL_CONF.tmp" && mv -f "$INSTALL_CONF.tmp" "$INSTALL_CONF"
    done
    chmod 644 "$INSTALL_CONF"
    echo "✅ Install settings written to $INSTALL_CONF:$INSTALL_SETTINGS"
fi

# File sharing is opt-in (#273 Q3) and Samba is not a package dependency. With
# QUOTIENT_INSTALL_SAMBA=include, install Samba before the package so postinst
# can add the Quotient share, and record that Quotient installed it (uninstall
# removes Samba only then). An existing Samba is used as it is.
if [ "${QUOTIENT_INSTALL_SAMBA:-}" = include ] && [ ! -x /usr/sbin/smbd ]; then
    echo "Installing Samba for file sharing (QUOTIENT_INSTALL_SAMBA=include)..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y samba; then
        echo "❌ Could not install Samba. Install it yourself (sudo apt-get install samba) and rerun,"
        echo "   or install without file sharing (leave QUOTIENT_INSTALL_SAMBA unset)."
        exit 1
    fi
    mkdir -p /var/lib/quotient/installed
    date -Iseconds > /var/lib/quotient/installed/samba
    echo "✅ Samba installed (recorded in /var/lib/quotient/installed/samba)"
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

# Write channel file so quotient-configure.sh and apply-k8s-manifests.sh use the correct image tags
mkdir -p /etc/quotient
echo "$CHANNEL" > /etc/quotient/channel
echo "✅ Release channel set to: ${CHANNEL}"

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
echo "  - Pull packages from: $REPO_URL (channel: ${CHANNEL})"
echo "  - Auto-update every hour on the hour (24/7, with jitter) via systemd timer"
echo "  - Deploy container images with tag: ${CHANNEL}"
echo ""
echo "To manually update: sudo apt-get update && sudo apt-get install -y quotient-server-tools"
echo "To check update status: systemctl status quotient-auto-update.timer"
echo "To change channel: edit /etc/quotient/channel and run: sudo apt-get update && sudo apt-get install -y quotient-server-tools"

# Setup link (ecosystem #372): apt's output is captured above, so the setup
# link postinst printed isn't shown. While the mainframe is not set up yet,
# end with it here.
if [ -f /var/lib/quotient/setup-code ] && command -v quotient >/dev/null 2>&1; then
    echo ""
    echo "=== Set up your mainframe ==="
    quotient setup-code || true
fi
