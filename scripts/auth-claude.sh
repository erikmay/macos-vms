#!/usr/bin/env bash
# Give VM N the Claude Code token from this Mac's Keychain (see token.sh).
. "$(dirname "$0")/lib.sh"
vm="$(vm_name "${1:-}")"

token="$(security find-generic-password -a "$USER" -s "$CLAUDE_TOKEN_KEYCHAIN_SERVICE" -w 2>/dev/null)" \
  || die "no Claude token in the Keychain. Run: make token"

log "Claude token -> $vm"
printf '%s' "$token" | host "$TART exec -i $vm zsh -c 'umask 077; mkdir -p ~/.config/agent-auth; cat > ~/.config/agent-auth/claude-oauth-token'"

# T3's launchd service does not read shell startup files: give it the token through launchd.
guest_script "$vm" < "$ROOT/guest/agent-env.sh"

log "Test prompt in $vm"
guest "$vm" 'cd ~/work && claude -p "Reply with exactly: ok" 2>&1 | tail -1'
