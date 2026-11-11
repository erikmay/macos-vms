#!/usr/bin/env bash
# Install or update everything that belongs in a VM image: agent CLIs, base agent
# settings, browser and computer use. Used for the golden image (image-build.sh)
# and to update an existing VM in place (make update). No credentials.
# Usage: provision.sh VM_NAME
. "$(dirname "$0")/lib.sh"
vm="${1:?usage: provision.sh VM_NAME}"

log "Agent CLIs in $vm (Claude Code, Codex, T3 $T3_VERSION)"
guest_script "$vm" "$T3_VERSION" < "$ROOT/guest/provision.sh"

log "Base agent settings in $vm"
guest_script "$vm" \
  "$(base64 < "$ROOT/guest/config/claude-settings.json" | tr -d '\n')" \
  "$(base64 < "$ROOT/guest/config/codex-config.toml" | tr -d '\n')" \
  < "$ROOT/guest/agent-config.sh"

log "Browser and computer use, voxl $VOXL_VERSION in $vm"
guest_script "$vm" "$VOXL_VERSION" < "$ROOT/guest/desktop.sh"
