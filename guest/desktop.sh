#!/bin/zsh
# Runs inside a VM (login zsh, guest user). Browser and computer use for agents.
# The design follows tobi/wrapvm (https://github.com/tobi/wrapvm), adapted to macOS:
#   - one persistent Google Chrome with its debugging port (CDP) on 127.0.0.1:9222.
#     It shows on the VM's screen, so a person can watch it and take over (make view).
#   - agent-browser attaches to that Chrome ({"headed": true, "autoConnect": true}).
#   - agent-desktop drives macOS apps through the accessibility tree
#     (its privacy permissions: guest/tcc-grant.sh).
#   - `browser` and `desktop` skills in ~/.agents/skills, linked into ~/.claude/skills.
#     They only load the guides that the two CLIs print, so they match the installed versions.
#   - voxl streams the screen to a browser for people (make view), with its own password.
# Idempotent; run it again to update the tools.
# Args: <voxl version>
set -euo pipefail
voxl_version="$1"

echo "--> Google Chrome"
[ -d "/Applications/Google Chrome.app" ] || brew install --cask google-chrome >/dev/null
# Without this, the first start waits in the "downloaded from the Internet" dialog.
xattr -dr com.apple.quarantine "/Applications/Google Chrome.app" 2>/dev/null || true

echo "--> agent-browser, agent-desktop"
npm install -g --allow-scripts=agent-browser,agent-desktop agent-browser@latest agent-desktop@latest >/dev/null

echo "--> Shared Chrome (CDP on 127.0.0.1:9222)"
# The job does not run Chrome itself. It runs a check, at login and every 30 seconds,
# that starts Chrome only if no Chrome with the agent profile runs. A job that runs the
# Chrome binary with KeepAlive breaks as soon as Chrome runs outside the job (after a
# Chrome update, or opened by hand): every new launch then exits at once and opens one
# more window in the running Chrome, forever.
label=macos-vms.agent-chrome
mkdir -p ~/Library/LaunchAgents ~/.config/agent-chrome
cat > ~/.config/agent-chrome/start.sh <<'SH'
#!/bin/zsh
profile="$HOME/.agent-chrome"
pgrep -f -- "--user-data-dir=$profile" >/dev/null && exit 0
exec open -n -a "Google Chrome" --args --remote-debugging-port=9222 \
  --remote-debugging-address=127.0.0.1 "--user-data-dir=$profile" \
  --no-first-run --no-default-browser-check --hide-crash-restore-bubble
SH
chmod 755 ~/.config/agent-chrome/start.sh
plist=~/Library/LaunchAgents/$label.plist
new="$(cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$HOME/.config/agent-chrome/start.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>30</integer>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PLIST
)"
if [ "$new" != "$(cat "$plist" 2>/dev/null)" ] || ! launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
  print -r -- "$new" > "$plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  for _ in {1..30}; do launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || break; sleep 1; done
  launchctl bootstrap "gui/$(id -u)" "$plist"
fi

# Never overwrite an existing config.
mkdir -p ~/.agent-browser
[ -f ~/.agent-browser/config.json ] || echo '{"headed": true, "autoConnect": true}' > ~/.agent-browser/config.json

echo "--> voxl $voxl_version (screen stream for make view)"
if ! ~/.cargo/bin/voxl --version 2>/dev/null | grep -q " $voxl_version\$"; then
  # Rust pulls in a large LLVM bottle; try a second time if a download fails.
  brew install x264 opus pkgconf esbuild rust >/dev/null || brew install x264 opus pkgconf esbuild rust >/dev/null
  cargo install --locked --quiet voxl-server --version "$voxl_version"
fi
# The password is made on the VM's first start, so clones of the golden image do not
# share one (image-build.sh removes it from the image). Softnet lets only the host
# reach port 6901; the host forwards it to its loopback.
mkdir -p ~/.config/voxl && chmod 700 ~/.config/voxl
# At every start: renew voxl's screen capture approval (see guest/tcc-grant.sh: an
# old or missing date makes replayd show a prompt), then run voxl.
cat > ~/.config/voxl/start.sh <<'SH'
#!/bin/zsh
f=~/.config/voxl/password
[ -s "$f" ] || (umask 077; openssl rand -hex 16 > "$f")
pkill -9 -x replayd 2>/dev/null
defaults write ~/Library/Group\ Containers/group.com.apple.replayd/ScreenCaptureApprovals \
  ~/.cargo/bin/voxl -dict-add kScreenCaptureApprovalLastUsed -date "$(date -u '+%Y-%m-%d %H:%M:%S +0000')"
export VOXL_PASSWORD="$(<"$f")"
exec ~/.cargo/bin/voxl --addr=0.0.0.0 --port=6901
SH
chmod 700 ~/.config/voxl/start.sh

# Grant the privacy permissions before the first start, or macOS shows a prompt.
# voxl captures the screen and sends input. The prompt guard below runs agent-desktop
# from launchd, and there macOS checks the agent-desktop binary itself (Accessibility only).
# (Writing the system TCC database needs SIP off, as in the Cirrus Labs images.)
agent_desktop="$(readlink -f "$(command -v agent-desktop)")"
for client in ~/.cargo/bin/voxl "$agent_desktop"; do
  for service in kTCCServiceAccessibility kTCCServiceScreenCapture kTCCServicePostEvent; do
    [ "$client" = "$agent_desktop" ] && [ "$service" != kTCCServiceAccessibility ] && continue
    sudo -n sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "INSERT OR REPLACE INTO access
      (service, client, client_type, auth_value, auth_reason, auth_version, flags)
      VALUES ('$service', '$client', 1, 2, 0, 1, NULL);"
  done
done
sudo -n killall tccd 2>/dev/null || true

# Prompt guard: macOS asks "Allow ... to find devices on local networks?" the first
# time T3 (or voxl, Chrome) uses the network of the VM. Nobody sits at the VM, so a
# LaunchAgent answers "Allow" through the accessibility API (a synthetic mouse click
# does not work on these dialogs). It answers only this prompt and only for these apps.
cat > ~/.config/voxl/prompt-guard.sh <<'SH'
#!/bin/zsh
export PATH=/opt/homebrew/bin:/usr/bin:/bin
snap="$(agent-desktop snapshot --app UserNotificationCenter 2>/dev/null)" || exit 0
ref="$(print -r -- "$snap" | /usr/bin/python3 -c '
import json, re, sys
texts, allow = [], None
def walk(n):
    global allow
    if isinstance(n, dict):
        if n.get("role") == "statictext": texts.append(n.get("name") or "")
        if n.get("role") == "button" and n.get("name") == "Allow": allow = n.get("ref_id")
        for v in n.values(): walk(v)
    elif isinstance(n, list):
        for v in n: walk(v)
walk(json.load(sys.stdin))
if allow and any(re.match("Allow “(t3|voxl|Google Chrome)” to find devices on local networks", t) for t in texts):
    print(allow)
' 2>/dev/null)"
[ -n "$ref" ] && agent-desktop click "$ref" >/dev/null 2>&1
exit 0
SH
chmod 700 ~/.config/voxl/prompt-guard.sh
cat > ~/Library/LaunchAgents/macos-vms.prompt-guard.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>macos-vms.prompt-guard</string>
  <key>ProgramArguments</key><array><string>$HOME/.config/voxl/prompt-guard.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>10</integer>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/macos-vms.prompt-guard" 2>/dev/null || true
for _ in {1..10}; do launchctl print "gui/$(id -u)/macos-vms.prompt-guard" >/dev/null 2>&1 || break; sleep 1; done
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/macos-vms.prompt-guard.plist
label=macos-vms.voxl
plist=~/Library/LaunchAgents/$label.plist
new="$(cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$HOME/.config/voxl/start.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>StandardErrorPath</key><string>/tmp/voxl.log</string>
</dict></plist>
PLIST
)"
if [ "$new" != "$(cat "$plist" 2>/dev/null)" ] || ! launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
  print -r -- "$new" > "$plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  for _ in {1..30}; do launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || break; sleep 1; done
  launchctl bootstrap "gui/$(id -u)" "$plist"
else
  # Same job, maybe a new binary: restart it.
  launchctl kickstart -k "gui/$(id -u)/$label"
fi

echo "--> Skills"
mkdir -p ~/.agents/skills/browser ~/.agents/skills/desktop ~/.claude/skills
cat > ~/.agents/skills/browser/SKILL.md <<'MD'
---
name: browser
description: Browser use - open pages, read them, click, fill forms, take screenshots - in the Chrome on this VM's screen, with the agent-browser CLI.
---
For anything in a web page we use `agent-browser`. It drives the one Google Chrome on this macOS VM's screen (CDP on 127.0.0.1:9222), which a person may be watching over Screen Sharing and can take over. Load its current guide before the first command:

!`agent-browser skills get core`
MD
cat > ~/.agents/skills/desktop/SKILL.md <<'MD'
---
name: desktop
description: Computer use - see and act on this VM's macOS apps, windows, menus, dialogs and the clipboard - with the agent-desktop CLI.
---
For computer use outside a web page we use `agent-desktop`. It drives the apps on this macOS VM's screen through the accessibility tree; a person may be watching over Screen Sharing and can take over. Load its current guides before the first command:

!`agent-desktop skills get desktop`

!`agent-desktop skills get platform`
MD
for s in browser desktop; do ln -sfn ~/.agents/skills/$s ~/.claude/skills/$s; done

for _ in {1..20}; do curl -fsS -o /dev/null http://127.0.0.1:9222/json/version 2>/dev/null && break; sleep 1; done
chrome="$(curl -fsS http://127.0.0.1:9222/json/version | sed -nE 's/.*"Browser": "([^"]+)".*/\1/p')"
for _ in {1..20}; do curl -fsS -o /dev/null http://127.0.0.1:6901/healthz 2>/dev/null && break; sleep 1; done
if curl -fsS -o /dev/null http://127.0.0.1:6901/healthz 2>/dev/null; then voxl="voxl answers"; else voxl="voxl does not answer yet (see /tmp/voxl.log)"; fi
echo "$chrome, $(agent-browser --version), agent-desktop $(agent-desktop version | sed -E 's/.*"version":"([^"]+)".*/\1/'), $voxl"
