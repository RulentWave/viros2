#!/usr/bin/env bash
# /usr/local/bin/ninja-sandboxed
set -euo pipefail

URL="${1:-}"

# Private state dir that masks the real $HOME inside the sandbox.
SANDBOX_HOME="$HOME/.ninja-sandbox-home"
mkdir -p "$SANDBOX_HOME"

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

TEMP_DIR="/tmp/ninja"
NCPLAYER_VERSION="13.35.8340"
NCPLAYER_EXPECTED_HASH="40cbcffeb1a64301d988114c9e7cfad11ac81115a0bbb1c4e05f9e1ecb67a0fc"
NCPLAYER_URL="https://resources.ninjarmm.com/development/ninjacontrol/${NCPLAYER_VERSION}/ninjarmm-ncplayer-${NCPLAYER_VERSION}_x86_64.rpm"
NCPLAYER_RPM="${TEMP_DIR}/ninjarmm-ncplayer-${NCPLAYER_VERSION}_x86_64.rpm"
NCPLAYER_BIN="/opt/ncplayer/bin/ncplayer"

H264_URL="http://ciscobinary.openh264.org/libopenh264-2.6.0-linux64.8.so.bz2"
DEST_DIR="/opt/ncplayer/bin"
H264_DEST_FILE="${DEST_DIR}/libopenh264-2.6.0-linux64.8.so"
H264_EXPECTED_HASH="2f0cde7c6a6abcf5cae76942894ea42897fa677bce4ed6c91a24dd1b041d5f04"
H264_TEMP_FILE="${TEMP_DIR}/libopenh264.so.bz2"

cleanup() {
	rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Returns 0 if ncplayer is already installed at the expected version.
ncplayer_installed() {
	if ! command -v rpm >/dev/null 2>&1; then
		# Fall back to checking for the binary if rpm isn't available.
		[[ -x "$NCPLAYER_BIN" ]]
		return
	fi
	rpm -q "ninjarmm-ncplayer-${NCPLAYER_VERSION}" >/dev/null 2>&1
}

install_ncplayer() {
	mkdir -p "$TEMP_DIR"
	echo "Downloading ninjarmm-ncplayer ${NCPLAYER_VERSION}..."
	wget -q --show-progress -O "$NCPLAYER_RPM" "$NCPLAYER_URL"

	local actual_hash
	actual_hash=$(sha256sum "$NCPLAYER_RPM" | awk '{print $1}')

	if [[ "$actual_hash" != "$NCPLAYER_EXPECTED_HASH" ]]; then
		echo "Error: ninjarmm-ncplayer hash mismatch!" >&2
		echo "  Expected: $NCPLAYER_EXPECTED_HASH" >&2
		echo "  Got:      $actual_hash" >&2
		exit 1
	fi

	# sudo should be NOPASSWD inside distrobox
	sudo dnf install -y "$NCPLAYER_RPM"
	echo "ninjarmm-ncplayer installed."
}

install_libopenh264() {
	if [[ -f "$H264_DEST_FILE" ]]; then
		echo "libopenh264 already present at $H264_DEST_FILE. Skipping."
		return 0
	fi

	echo "Downloading libopenh264..."
	mkdir -p "$TEMP_DIR"
	if ! curl -fSL --connect-timeout 10 "$H264_URL" -o "$H264_TEMP_FILE"; then
		echo "Warning: failed to download libopenh264. Continuing without it." >&2
		return 0
	fi

	local tmp_so="${TEMP_DIR}/libopenh264.so"
	if ! bzip2 -dc "$H264_TEMP_FILE" >"$tmp_so"; then
		echo "Warning: failed to decompress libopenh264. Continuing without it." >&2
		return 0
	fi

	local actual_hash
	actual_hash=$(sha256sum "$tmp_so" | awk '{print $1}')

	if [[ "$actual_hash" != "$H264_EXPECTED_HASH" ]]; then
		echo "Warning: libopenh264 hash mismatch! Expected $H264_EXPECTED_HASH, got $actual_hash." >&2
		echo "Continuing without libopenh264." >&2
		return 0
	fi

	sudo install -m 0755 "$tmp_so" "$H264_DEST_FILE"
	echo "libopenh264 installed at $H264_DEST_FILE."
}

# Ensure destination directory exists (sudo NOPASSWD inside distrobox)
sudo mkdir -p "$DEST_DIR"

if ncplayer_installed; then
	echo "ninjarmm-ncplayer ${NCPLAYER_VERSION} already installed. Skipping."
else
	install_ncplayer
fi

install_libopenh264

# Optional: filtered dbus proxy (uncomment if app needs notifications/tray)
# DBUS_PROXY_SOCK="$RUNTIME/ninja-bus"
# rm -f "$DBUS_PROXY_SOCK"
# xdg-dbus-proxy --fd=0 \
#   "$DBUS_SESSION_BUS_ADDRESS" "$DBUS_PROXY_SOCK" \
#   --filter \
#   --talk=org.freedesktop.Notifications \
#   --talk=org.kde.StatusNotifierWatcher &
# DBUS_PID=$!
# trap 'kill $DBUS_PID 2>/dev/null || true' EXIT
# sleep 0.2

exec bwrap \
	`# --- read-only system ---` \
	--ro-bind /usr /usr \
	--ro-bind /etc /etc \
	--ro-bind /opt /opt \
	--symlink usr/lib /lib \
	--symlink usr/lib64 /lib64 \
	--symlink usr/bin /bin \
	--symlink usr/sbin /sbin \
	\
	`# --- kernel/pseudo filesystems ---` \
	--proc /proc \
	--dev /dev \
	--tmpfs /tmp \
	--tmpfs /var/tmp \
	--tmpfs /run \
	\
	`# --- isolated home ---` \
	--bind "$SANDBOX_HOME" "$HOME" \
	--setenv HOME "$HOME" \
	--chdir "$HOME" \
	\
	`# --- runtime dir: only what's needed ---` \
	--tmpfs "$RUNTIME" \
	--ro-bind-try "$RUNTIME/wayland-0" "$RUNTIME/wayland-0" \
	--ro-bind-try "$RUNTIME/pulse" "$RUNTIME/pulse" \
	--ro-bind-try /tmp/.X11-unix/X0 /tmp/.X11-unix/X0 \
	`# --- uncomment if using filtered dbus above ---` \
	`# --bind "$DBUS_PROXY_SOCK" "$RUNTIME/bus"` \
	`# --setenv DBUS_SESSION_BUS_ADDRESS "unix:path=$RUNTIME/bus"` \
	\
	`# --- network (needed for remote support) ---` \
	--share-net \
	--ro-bind /etc/resolv.conf /etc/resolv.conf \
	\
	`# --- env ---` \
	--setenv XDG_RUNTIME_DIR "$RUNTIME" \
	--setenv WAYLAND_DISPLAY "${WAYLAND_DISPLAY:-wayland-0}" \
	--setenv DISPLAY "${DISPLAY:-:0}" \
	\
	--ro-bind-try /tmp/.X11-unix /tmp/.X11-unix \
	--ro-bind-try "${XAUTHORITY:-$HOME/.Xauthority}" /tmp/.Xauthority \
	--setenv XAUTHORITY /tmp/.Xauthority \
	`# --- hardening ---` \
	--unshare-user \
	--unshare-pid \
	--unshare-uts \
	--unshare-ipc \
	--unshare-cgroup-try \
	--new-session \
	--die-with-parent \
	--cap-drop ALL \
	\
	-- "$NCPLAYER_BIN" "$URL"
