#!/usr/bin/env bash
# Show each VM: state, the T3 server seen from this Mac, tool versions and logins.
. "$(dirname "$0")/lib.sh"

vms="$(vm_list)"
[ -n "$vms" ] || { echo "No VMs on $VM_HOST. Run: make up N=1"; exit 0; }

for vm in $vms; do
  n="${vm#"$VM_PREFIX"}"
  if ! vm_running "$vm"; then
    printf '%s  stopped\n' "$vm"
    continue
  fi
  t3="$(curl -fsS -m 5 "http://127.0.0.1:$(t3_local_port "$n")/.well-known/t3/environment" 2>/dev/null \
    | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d["serverVersion"])' 2>/dev/null || true)"
  printf '%s  running\n' "$vm"
  if [ -n "$t3" ]; then
    printf '  %-8s %s, reachable on 127.0.0.1:%s\n' "T3" "$t3" "$(t3_local_port "$n")"
  else
    printf '  %-8s not reachable on 127.0.0.1:%s (try: make tunnel, make update N=%s)\n' "T3" "$(t3_local_port "$n")" "$n"
  fi
  guest "$vm" '
    v() { "$@" 2>/dev/null | head -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo missing; }
    [ -s ~/.config/agent-auth/claude-oauth-token ] && c="token set" || c="no token"
    codex login status 2>&1 | grep -q "^Logged in" && x="logged in" || x="not logged in"
    printf "  %-8s %s, %s\n" "Claude" "$(v claude --version)" "$c"
    printf "  %-8s %s, %s\n" "Codex" "$(v codex --version)" "$x"
    printf "  %-8s agent-browser %s, agent-desktop %s\n" "Desktop" "$(v agent-browser --version)" "$(v agent-desktop version)"
  ' 2>/dev/null || printf '  guest agent does not answer\n'
done
