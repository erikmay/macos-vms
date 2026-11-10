#!/usr/bin/env bash
# Open Screen Sharing for VM N to watch the agent or take over.
# Login: the image's user, admin / admin for the Cirrus Labs images.
. "$(dirname "$0")/lib.sh"
n="${1:-}"
vm="$(vm_name "$n")"
port="$(vnc_local_port "$n")"

nc -z 127.0.0.1 "$port" 2>/dev/null || die "127.0.0.1:$port does not answer. Run: make tunnel"
log "Screen Sharing for $vm (127.0.0.1:$port)"
open "vnc://127.0.0.1:$port"
