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
# Idempotent; run it again to update the tools.
set -euo pipefail

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
  --no-first-run --no-default-browser-check
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
echo "$chrome, $(agent-browser --version), agent-desktop $(agent-desktop version | sed -E 's/.*"version":"([^"]+)".*/\1/')"
