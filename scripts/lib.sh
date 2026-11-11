#!/usr/bin/env bash
# Shared helpers, sourced by every script: . "$(dirname "$0")/lib.sh"
#
# Three machines are involved:
#   client  this Mac: runs these scripts and the T3 Code desktop app
#   host    the Mac that runs the VMs ($VM_HOST, reached over SSH, or `local`)
#   guest   a macOS VM on the host (reached through `tart exec`)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/config.env"
# shellcheck disable=SC1091
if [ -f "$ROOT/config.local.env" ]; then . "$ROOT/config.local.env"; fi

# Fixed names, used by the scripts that source this file.
# shellcheck disable=SC2034
{
  LAUNCHD_PREFIX=macos-vms   # launchd labels on the host and the client; the guest scripts use the same
  T3_PORT=3773               # T3 server port inside a VM
  VNC_PORT=5900              # Screen Sharing port inside a VM
  VOXL_PORT=6901             # voxl port inside a VM
}
# shellcheck disable=SC2016  # expanded by the host's shell, not here
TART='"$HOME/bin/tart"'      # installed by `make host`

# TIMING=1 prefixes each log line with the seconds since the first script started.
if [ -n "${TIMING:-}" ]; then export TIMING_T0="${TIMING_T0:-$(date +%s)}"; fi
log() {
  local t=""
  if [ -n "${TIMING:-}" ]; then t="[$(( $(date +%s) - TIMING_T0 ))s] "; fi
  printf '\033[1;34m==>\033[0m %s%s\n' "$t" "$*" >&2
}
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -n "${VM_HOST:-}" ] || die "VM_HOST is not set. Run: echo 'VM_HOST=<ssh host or local>' > $ROOT/config.local.env"

is_local_host() { [ "$VM_HOST" = local ]; }

# vm_name N -> mac-vmN
vm_name() {
  [[ "${1:-}" =~ ^[0-9]$ ]] || die "set N to a VM number, for example: make up N=1"
  echo "${VM_PREFIX}$1"
}
t3_local_port()  { echo $((T3_LOCAL_PORT_BASE + $1)); }
vnc_local_port() { echo $((VNC_LOCAL_PORT_BASE + $1)); }
voxl_local_port() { echo $((VOXL_LOCAL_PORT_BASE + $1)); }

# Run a shell command line on the host.
host() {
  if is_local_host; then bash -c "$*"; else ssh "$VM_HOST" "$*"; fi
}

# Run a bash script (stdin) on the host. Arguments must not contain spaces.
host_script() {
  if is_local_host; then bash -s -- "$@"; else ssh "$VM_HOST" "bash -s -- $*"; fi
}

# Run a zsh script (stdin) inside a VM as the guest user, in a login shell.
# Usage: guest_script VM [args...] < script. Arguments must not contain spaces.
guest_script() {
  local vm="$1"; shift
  host "$TART exec -i $vm zsh -l -s -- $*"
}

# Run one command line inside a VM.
guest() {
  local vm="$1"; shift
  printf '%s\n' "$*" | guest_script "$vm"
}

# Names of this project's VMs on the host, sorted.
vm_list() {
  host "$TART list --source local --quiet" | grep -E "^${VM_PREFIX}[0-9]$" | sort || true
}

vm_exists()  { host "$TART list --source local --quiet" | grep -qx "$1"; }
vm_running() { host "$TART list --source local --format json" | python3 -I -c '
import json, sys
sys.exit(0 if any(v["Name"] == sys.argv[1] and v["Running"] for v in json.load(sys.stdin)) else 1)' "$1"; }

# Number of running macOS guests on the host (Apple allows 2).
running_count() {
  host "$TART list --source local --format json" | python3 -I -c '
import json, sys
print(sum(1 for v in json.load(sys.stdin) if v["Running"]))'
}

# Wait until the VM has an IP and its guest agent answers.
vm_wait() {
  host "$TART ip --wait 180 $1" >/dev/null
  local _
  for _ in $(seq 1 60); do
    if guest "$1" true 2>/dev/null; then return 0; fi
    sleep 5
  done
  die "$1 did not answer on the Tart guest agent"
}

# Install or update a LaunchAgent (plist on stdin). WHERE is `host` or `client`.
# It is reloaded only when the plist changed.
launchd_install() {
  local where="$1" label="$2" plist
  plist="$(base64 | tr -d '\n')"
  if [ "$where" = host ]; then
    host_script install "$label" "$plist" < "$ROOT/scripts/launchd.sh"
  else
    bash "$ROOT/scripts/launchd.sh" install "$label" "$plist"
  fi
}

# Unload and delete a LaunchAgent. WHERE is `host` or `client`.
launchd_remove() {
  local where="$1" label="$2"
  if [ "$where" = host ]; then
    host_script remove "$label" < "$ROOT/scripts/launchd.sh"
  else
    bash "$ROOT/scripts/launchd.sh" remove "$label"
  fi
}
