#!/usr/bin/env bash
# Log in Codex in VM N with the device-code flow. It prints a link and a one-time
# code and waits until you approve it in a browser. Every VM gets its own login:
# a Codex auth.json must not be copied between machines.
. "$(dirname "$0")/lib.sh"
vm="$(vm_name "${1:-}")"

if guest "$vm" 'codex login status 2>&1' | grep -q '^Logged in'; then
  log "Codex is already logged in on $vm"
  exit 0
fi
log "Codex device login on $vm"
guest "$vm" 'codex login --device-auth'
guest "$vm" 'codex login status'
