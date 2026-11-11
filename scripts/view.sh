#!/usr/bin/env bash
# Show the VMs' screens side by side in one browser page, streamed by voxl: watch the
# agents and take over with mouse and keyboard.
#   view.sh      all VMs
#   view.sh N    VM N only
# The page embeds each VM's voxl password, so it is written to this Mac's user cache
# (mode 600), not to the repository. A LaunchAgent serves it on 127.0.0.1:<VOXL_LOCAL_PORT_BASE>
# (scripts/view-server.py): Chrome blocks a file:// page from loading the streams on
# 127.0.0.1 (Local Network Access), but allows a page that is on loopback itself.
# `make vnc` is the Screen Sharing fallback.
. "$(dirname "$0")/lib.sh"

if [ -n "${1:-}" ]; then
  vms="$(vm_name "$1")"
else
  vms="$(vm_list)"
  [ -n "$vms" ] || die "no VMs on $VM_HOST"
fi

panes=""
for vm in $vms; do
  port="$(voxl_local_port "${vm#"$VM_PREFIX"}")"
  curl -fsS -o /dev/null "http://127.0.0.1:$port/healthz" 2>/dev/null \
    || die "voxl of $vm does not answer on 127.0.0.1:$port. Run: make tunnel (or make update N=${vm#"$VM_PREFIX"})"
  password="$(guest "$vm" 'cat ~/.config/voxl/password')"
  [[ "$password" =~ ^[0-9a-f]+$ ]] || die "no voxl password in $vm"
  panes="$panes{\"name\":\"$vm\",\"url\":\"http://127.0.0.1:$port/?token=$password\"},"
done

page="$HOME/Library/Caches/macos-vms/view.html"
mkdir -p "${page%/*}"
(umask 077; cat > "$page") <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>macos-vms</title>
<style>
  html, body { margin: 0; height: 100%; background: #0b0b0d; color: #ccc; font: 12px system-ui; }
  #grid { display: grid; gap: 4px; height: 100vh; padding: 4px; box-sizing: border-box; }
  .pane { display: flex; flex-direction: column; min-width: 0; min-height: 0; background: #000;
    border-radius: 6px; overflow: hidden; }
  .bar { display: flex; align-items: center; justify-content: space-between; height: 22px;
    padding: 0 8px; background: #17171c; flex: none; }
  .bar button { background: none; border: 0; color: #aaa; cursor: pointer; font-size: 14px; }
  .bar button:hover { color: #fff; }
  iframe { flex: 1; width: 100%; border: 0; }
  #grid.focused { grid-template: 1fr / 1fr !important; }
  #grid.focused .pane:not(.max) { display: none; }
</style>
</head>
<body>
<div id="grid"></div>
<script>
// One pane per VM: voxl's own page in an iframe. A pane hidden behind a maximized
// one disconnects, so voxl encodes nothing for it.
const vms = [${panes%,}];
const grid = document.getElementById("grid");
let maximized;
const cols = Math.ceil(Math.sqrt(vms.length));
grid.style.gridTemplateColumns = "repeat(" + cols + ", 1fr)";
grid.style.gridTemplateRows = "repeat(" + Math.ceil(vms.length / cols) + ", 1fr)";
const panes = vms.map((vm) => {
  const el = document.createElement("div");
  el.className = "pane";
  const bar = document.createElement("div");
  bar.className = "bar";
  const label = document.createElement("span");
  label.textContent = vm.name;
  const button = document.createElement("button");
  button.title = "Maximize";
  button.textContent = "⤢";
  button.onclick = () => { maximized = maximized === vm.name ? undefined : vm.name; layout(); };
  bar.append(label, button);
  const frame = document.createElement("iframe");
  frame.allow = "clipboard-read; clipboard-write; fullscreen; autoplay";
  el.append(bar, frame);
  grid.append(el);
  return { el, frame, vm };
});
function layout() {
  grid.classList.toggle("focused", maximized !== undefined);
  for (const p of panes) {
    p.el.classList.toggle("max", p.vm.name === maximized);
    const want = !maximized || maximized === p.vm.name ? p.vm.url : "about:blank";
    if (p.frame.src !== want) p.frame.src = want;
  }
}
layout();
</script>
</body>
</html>
HTML

# Install or update the page server (client LaunchAgent).
server_dir="$HOME/Library/Application Support/macos-vms"
mkdir -p "$server_dir"
changed=""
cmp -s "$ROOT/scripts/view-server.py" "$server_dir/view-server.py" || { cp "$ROOT/scripts/view-server.py" "$server_dir/view-server.py"; changed=1; }
launchd_install client "$LAUNCHD_PREFIX.view" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LAUNCHD_PREFIX.view</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/python3</string><string>-I</string>
    <string>$server_dir/view-server.py</string>
    <string>$VOXL_LOCAL_PORT_BASE</string><string>$page</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
PLIST
if [ -n "$changed" ]; then launchctl kickstart -k "gui/$(id -u)/$LAUNCHD_PREFIX.view"; fi
url="http://127.0.0.1:$VOXL_LOCAL_PORT_BASE/"
for _ in $(seq 1 20); do curl -fsS -o /dev/null "$url" 2>/dev/null && break; sleep 0.5; done

log "Opening the screens of: ${vms//$'\n'/, } ($url)"
open "$url"
