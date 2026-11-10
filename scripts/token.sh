#!/usr/bin/env bash
# Store the Claude Code long-lived token in this Mac's Keychain. Make the token
# first with `claude setup-token`; `make auth N=…` copies it into a VM.
. "$(dirname "$0")/lib.sh"

echo "Paste the token from 'claude setup-token' (input is hidden, asked twice):"
security add-generic-password -U -a "$USER" -s "$CLAUDE_TOKEN_KEYCHAIN_SERVICE" -w
log "Stored in the Keychain item $CLAUDE_TOKEN_KEYCHAIN_SERVICE"
