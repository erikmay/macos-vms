#!/usr/bin/env bash
# Update VM N in place: run the same provisioning as the golden image, then make
# sure the T3 service runs the configured version. Logins and data stay.
. "$(dirname "$0")/lib.sh"
vm="$(vm_name "${1:-}")"

"$ROOT/scripts/provision.sh" "$vm"
"$ROOT/scripts/vm-t3.sh" "$1"
