#!/usr/bin/env bash
# Prepare the host: Tart (runs the VMs), Softnet (network isolation) and socat
# (port forwarders). Idempotent.
. "$(dirname "$0")/lib.sh"

log "Checking $VM_HOST"
host_script <<'EOF'
set -euo pipefail
[ "$(uname -sm)" = "Darwin arm64" ] || { echo "the host must be an Apple Silicon Mac" >&2; exit 1; }
launchctl print "gui/$(id -u)" >/dev/null 2>&1 || {
  echo "no desktop session for $(id -un): log in on the host's screen (or enable automatic login)" >&2; exit 1; }
[ -x /opt/homebrew/bin/brew ] || { echo "Homebrew is missing on the host: https://brew.sh" >&2; exit 1; }
echo "macOS $(sw_vers -productVersion), $(sysctl -n hw.memsize | awk '{printf "%d GB RAM", $1/1073741824}')"
EOF

# From the GitHub release, not Homebrew: the scripts depend on a pinned version at a fixed path.
log "Tart $TART_VERSION"
host_script "$TART_VERSION" <<'EOF'
set -euo pipefail
v="$1"
if [ -x "$HOME/bin/tart" ] && "$HOME/bin/tart" --version | grep -qx "$v"; then
  echo "already installed"; exit 0
fi
mkdir -p "$HOME/opt/tart" "$HOME/bin"
cd "$HOME/opt/tart"
curl -fsSL -o tart.tar.gz "https://github.com/cirruslabs/tart/releases/download/$v/tart.tar.gz"
rm -rf tart.app && tar xzf tart.tar.gz && rm tart.tar.gz
ln -sf "$HOME/opt/tart/tart.app/Contents/MacOS/tart" "$HOME/bin/tart"
"$HOME/bin/tart" --version
EOF

# Softnet must be SUID root to create the VM's network interface.
log "Softnet $SOFTNET_VERSION"
host_script "$SOFTNET_VERSION" <<'EOF'
set -euo pipefail
v="$1"
if /usr/local/bin/softnet --version 2>/dev/null | grep -q "^softnet $v"; then
  echo "already installed"; exit 0
fi
tmp="$(mktemp -d)"
curl -fsSL "https://github.com/cirruslabs/softnet/releases/download/$v/softnet.tar.gz" | tar xz -C "$tmp"
if ! sudo -n install -d /usr/local/bin || ! sudo -n install -o root -g wheel -m 4755 "$tmp/softnet" /usr/local/bin/softnet; then
  echo "sudo needs a password. Run this on the host, then run 'make host' again:" >&2
  echo "  sudo install -d /usr/local/bin && sudo install -o root -g wheel -m 4755 $tmp/softnet /usr/local/bin/softnet" >&2
  exit 1
fi
rm -rf "$tmp"
/usr/local/bin/softnet --version
EOF

log "socat"
host '[ -x /opt/homebrew/bin/socat ] || /opt/homebrew/bin/brew install socat >/dev/null; /opt/homebrew/bin/socat -V | sed -n 2p'
