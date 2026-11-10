#!/usr/bin/env bash
# Build the golden image: the base image plus everything provision.sh installs.
# VMs are clones of it. Needs one free macOS VM slot on the host.
. "$(dirname "$0")/lib.sh"

build="${GOLDEN_IMAGE}-build"

[ "$(running_count)" -lt 2 ] || die "2 macOS VMs are running, which is Apple's limit. Stop one first: make stop N=2 (and make start N=2 afterwards)"

log "Cloning $BASE_IMAGE -> $build (the first pull downloads about 27 GB)"
host "$TART delete $build 2>/dev/null || true; $TART clone $BASE_IMAGE $build && $TART set $build --cpu $VM_CPU --memory $VM_MEMORY_MB"

log "Booting $build"
trap 'host "$TART stop $build" >/dev/null 2>&1 || true' ERR
host "PATH=/usr/local/bin:\$PATH nohup $TART run $TART_RUN_FLAGS $build >/tmp/$build.log 2>&1 &"
vm_wait "$build"

"$ROOT/scripts/provision.sh" "$build"

log "Saving as $GOLDEN_IMAGE"
host "$TART stop $build && { $TART delete $GOLDEN_IMAGE 2>/dev/null || true; } && $TART rename $build $GOLDEN_IMAGE"
log "Done. Create VMs with: make up N=1"
