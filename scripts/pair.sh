#!/usr/bin/env bash
# Pair the T3 Code desktop app on this Mac with VM N: make a one-time pairing token
# in the VM and open the app's pairing link for the VM's local tunnel port.
. "$(dirname "$0")/lib.sh"
n="${1:-}"
vm="$(vm_name "$n")"
port="$(t3_local_port "$n")"

curl -fsS -o /dev/null "http://127.0.0.1:$port/" || die "127.0.0.1:$port does not answer. Run: make tunnel"

token="$(guest "$vm" "t3 pair --label $(hostname -s) --ttl 10m 2>&1" | awk '/^Token:/{print $2}')"
[ -n "$token" ] || die "t3 pair gave no token in $vm"

url="$(python3 -I -c '
import sys, urllib.parse
pairing = f"http://127.0.0.1:{sys.argv[1]}/pair#token={sys.argv[2]}"
print("t3code://pair?" + urllib.parse.urlencode({"pairingUrl": pairing}))' "$port" "$token")"
open "$url"
log "Opened the pairing link for $vm in T3 Code (127.0.0.1:$port)"
