#!/usr/bin/env bash
# Run the T3 Code server in VM N as a background service, without a T3 account
# (no T3 Connect). The server accepts network connections, but with Softnet only
# the host can reach the VM, and a client still needs a pairing code (pair.sh).
. "$(dirname "$0")/lib.sh"
vm="$(vm_name "${1:-}")"

log "T3 service in $vm"
guest_script "$vm" "$T3_PORT" <<'EOF'
set -euo pipefail
port="$1"
cd ~/work
t3 up --lan --no-connect --yes 2>&1 | grep -E '^ *(Service|T3 Connect|Local network)' || true
for _ in {1..30}; do lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1 && exit 0; sleep 2; done
echo "T3 does not listen on port $port; see ~/.t3/userdata/logs" >&2; exit 1
EOF

# agent-desktop needs macOS privacy permissions; they belong to the T3 runtime binary.
log "Privacy permissions for agents started by T3 in $vm"
guest_script "$vm" < "$ROOT/guest/tcc-grant.sh"
