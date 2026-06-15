#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./install-rpm-if-sha256-matches.sh <rpm_url> <expected_sha256>
#
# Example:
#   ./install-rpm-if-sha256-matches.sh \
#     "https://example.com/package.rpm" \
#     "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

RPM_URL='https://opencode.ai/download/stable/linux-x64-rpm'
EXPECTED_SHA256='b2b6a6c9665b419679ff257efdc9dc333f6558215612d54f8106e90ee4e96067'

if [[ -z "$RPM_URL" || -z "$EXPECTED_SHA256" ]]; then
	echo "Usage: $0 <rpm_url> <expected_sha256>"
	exit 1
fi

if ! [[ "$EXPECTED_SHA256" =~ ^[a-fA-F0-9]{64}$ ]]; then
	echo "Error: expected SHA256 must be a 64-character hex string"
	exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
	echo "Error: this script must be run as root"
	exit 1
fi

TMP_DIR="$(mktemp -d)"
RPM_FILE="$TMP_DIR/package.rpm"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading RPM from:"
echo "  $RPM_URL"

curl -fL --retry 3 --connect-timeout 15 -o "$RPM_FILE" "$RPM_URL"

echo "Checking SHA256 hash..."

ACTUAL_SHA256="$(sha256sum "$RPM_FILE" | awk '{print $1}')"

EXPECTED_SHA256_LOWER="$(echo "$EXPECTED_SHA256" | tr 'A-F' 'a-f')"
ACTUAL_SHA256_LOWER="$(echo "$ACTUAL_SHA256" | tr 'A-F' 'a-f')"

echo "Expected: $EXPECTED_SHA256_LOWER"
echo "Actual:   $ACTUAL_SHA256_LOWER"

if [[ "$ACTUAL_SHA256_LOWER" != "$EXPECTED_SHA256_LOWER" ]]; then
	echo "Error: SHA256 hash mismatch. Refusing to install."
	exit 1
fi

echo "SHA256 hash matches."

if command -v dnf >/dev/null 2>&1; then
	echo "Installing RPM with dnf..."
	dnf install -y "$RPM_FILE"
elif command -v yum >/dev/null 2>&1; then
	echo "Installing RPM with yum..."
	yum localinstall -y "$RPM_FILE"
else
	echo "Installing RPM with rpm..."
	rpm -Uvh "$RPM_FILE"
fi

echo "Installation complete."
