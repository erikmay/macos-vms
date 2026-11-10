#!/usr/bin/env bash
# Stop or start VM N. `stop` also unloads its launchd job, so it stays off until
# `start` (for example to free a VM slot for `make image`).
# Usage: vm-power.sh stop|start N
. "$(dirname "$0")/lib.sh"
action="${1:-}"
vm="$(vm_name "${2:-}")"

case "$action" in
  stop)
    log "Stopping $vm"
    host_script stop "$LAUNCHD_PREFIX.vm.$vm" < "$ROOT/scripts/launchd.sh"
    host "$TART stop $vm 2>/dev/null || true"
    ;;
  start)
    log "Starting $vm"
    host_script start "$LAUNCHD_PREFIX.vm.$vm" < "$ROOT/scripts/launchd.sh"
    vm_wait "$vm"
    ;;
  *) die "usage: vm-power.sh stop|start N" ;;
esac
