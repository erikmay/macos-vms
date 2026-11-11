#!/usr/bin/env bash
# Open the VMs' screens in macOS Screen Sharing (VNC), the fallback to `make view`.
#   vnc.sh      all VMs, their windows tiled side by side
#   vnc.sh N    VM N only
# The login in the vnc:// link (VM_USER, VM_PASSWORD) skips the sign-in dialog.
. "$(dirname "$0")/lib.sh"

if [ -n "${1:-}" ]; then
  vms="$(vm_name "$1")"
else
  vms="$(vm_list)"
  [ -n "$vms" ] || die "no VMs on $VM_HOST"
fi

for vm in $vms; do
  port="$(vnc_local_port "${vm#"$VM_PREFIX"}")"
  nc -z 127.0.0.1 "$port" 2>/dev/null || die "127.0.0.1:$port does not answer. Run: make tunnel"
  log "Screen Sharing for $vm (127.0.0.1:$port)"
  open "vnc://$VM_USER:$VM_PASSWORD@127.0.0.1:$port"
done

# Tile the windows left to right on the main screen. Screen Sharing names a window
# after the computer, which is the VM name. This needs the Accessibility permission
# for the app that runs this script; without it the windows stay where they opened.
# shellcheck disable=SC2086  # one argument per VM
osascript -l JavaScript - $vms <<'JXA' || log "Could not arrange the windows: allow your terminal under Privacy & Security > Accessibility"
ObjC.import('AppKit');
function run(names) {
  const screen = $.NSScreen.mainScreen;
  const visible = screen.visibleFrame;
  const top = screen.frame.size.height - (visible.origin.y + visible.size.height);
  const width = Math.floor(visible.size.width / names.length);
  const app = Application('System Events').processes.byName('Screen Sharing');
  names.forEach((name, i) => {
    let win;
    for (let t = 0; t < 30 && !win; t++) {
      win = app.windows().find(w => w.name() === name);
      if (!win) delay(0.5);
    }
    if (!win) return;
    win.position = [visible.origin.x + i * width, top];
    win.size = [width, visible.size.height];
  });
}
JXA
