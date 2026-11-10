#!/usr/bin/env bash
# Keep the logins of VM slot N across `make reset`: the Codex login and the T3 server
# identity (see guest/state.sh), stored in a Keychain item on this Mac per slot.
#   vm-state.sh save N      copy the state out of the running VM into the Keychain
#   vm-state.sh restore N   copy it from the Keychain into the VM (before T3 starts)
#   vm-state.sh sessions N  load the restored T3 app sessions (after T3 has started)
#   vm-state.sh forget N    delete the Keychain item (the next VM N starts without logins)
# The Codex login moves from the old VM to its replacement, never to a second
# running machine, so its single-use refresh token stays valid.
. "$(dirname "$0")/lib.sh"
action="${1:-}"
vm="$(vm_name "${2:-}")"
item="macos-vms-state-$vm"

case "$action" in
  save)
    vm_running "$vm" || { log "$vm is not running: its logins were not saved"; exit 0; }
    state="$(guest_script "$vm" save < "$ROOT/guest/state.sh" | tr -d '\n')"
    [ -n "$state" ] || { log "$vm has no logins to save"; exit 0; }
    security add-generic-password -U -a "$USER" -s "$item" -w "$state"
    log "Saved the logins of $vm in the Keychain"
    ;;
  restore)
    state="$(security find-generic-password -a "$USER" -s "$item" -w 2>/dev/null)" \
      || { log "No saved logins for $vm"; exit 0; }
    guest_script "$vm" restore "$state" < "$ROOT/guest/state.sh"
    log "Restored the saved logins into $vm"
    ;;
  sessions)
    guest_script "$vm" sessions < "$ROOT/guest/state.sh"
    ;;
  forget)
    security delete-generic-password -a "$USER" -s "$item" >/dev/null 2>&1 || true
    log "Forgot the saved logins of $vm"
    ;;
  *) die "usage: vm-state.sh save|restore|sessions|forget N" ;;
esac
