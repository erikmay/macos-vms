#!/usr/bin/env bash
# Delete VM N: its launchd jobs on the host, then the VM and its disk.
. "$(dirname "$0")/lib.sh"
vm="$(vm_name "${1:-}")"

log "Deleting $vm"
for job in vm fwd-t3 fwd-vnc; do launchd_remove host "$LAUNCHD_PREFIX.$job.$vm"; done
if vm_exists "$vm"; then
  host "$TART stop $vm 2>/dev/null || true; $TART delete $vm"
fi
