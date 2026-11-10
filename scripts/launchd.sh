#!/usr/bin/env bash
# Manage one LaunchAgent of the current user. Runs on the host or the client
# (see launchd_install / launchd_remove in lib.sh).
#   launchd.sh install LABEL PLIST_BASE64   install; reload only if the plist changed
#   launchd.sh remove  LABEL                unload and delete
#   launchd.sh stop    LABEL                unload, keep the plist
#   launchd.sh start   LABEL                load the existing plist
set -euo pipefail

action="$1"; label="$2"
dir="$HOME/Library/LaunchAgents"
plist="$dir/$label.plist"
domain="gui/$(id -u)"

loaded() { launchctl print "$domain/$label" >/dev/null 2>&1; }

unload() {
  launchctl bootout "$domain/$label" 2>/dev/null || true
  # bootout returns before the job is gone; bootstrap fails until it is.
  local _
  for _ in $(seq 1 30); do loaded || return 0; sleep 1; done
}

case "$action" in
  install)
    mkdir -p "$dir"
    tmp="$(mktemp)"
    printf '%s' "$3" | base64 -D > "$tmp"
    plutil -lint "$tmp" >/dev/null
    if cmp -s "$tmp" "$plist" && loaded; then rm -f "$tmp"; exit 0; fi
    mv "$tmp" "$plist"
    unload
    launchctl bootstrap "$domain" "$plist"
    ;;
  remove)
    unload
    rm -f "$plist"
    ;;
  stop)
    unload
    ;;
  start)
    [ -f "$plist" ] || { echo "no LaunchAgent $label" >&2; exit 1; }
    loaded || launchctl bootstrap "$domain" "$plist"
    ;;
  *)
    echo "usage: launchd.sh install|remove|stop|start LABEL [PLIST_BASE64]" >&2; exit 2
    ;;
esac
