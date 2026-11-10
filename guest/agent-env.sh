#!/bin/zsh
# Runs inside a VM. Installs a LaunchAgent that, at every login, exports the Claude
# Code token to launchd (`launchctl setenv`) and restarts the T3 service.
# Why: T3 runs as a launchd service and does not read shell startup files, so the
# agents it starts see only launchd's environment. Idempotent.
set -euo pipefail

dir=~/.config/agent-auth
mkdir -p "$dir" ~/Library/LaunchAgents && chmod 700 "$dir"

cat > "$dir/load.sh" <<'SH'
#!/bin/zsh
f=~/.config/agent-auth/claude-oauth-token
if [ -s "$f" ]; then
  launchctl setenv CLAUDE_CODE_OAUTH_TOKEN "$(<"$f")"
else
  launchctl unsetenv CLAUDE_CODE_OAUTH_TOKEN
fi
launchctl kickstart -k "gui/$(id -u)/com.t3tools.t3code.service" 2>/dev/null || true
SH
chmod 700 "$dir/load.sh"

label=macos-vms.agent-env
plist=~/Library/LaunchAgents/$label.plist
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$dir/load.sh</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
# Load it now: this runs load.sh once.
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
for _ in {1..30}; do launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || break; sleep 1; done
launchctl bootstrap "gui/$(id -u)" "$plist"

for _ in {1..10}; do [ -n "$(launchctl getenv CLAUDE_CODE_OAUTH_TOKEN)" ] && break; sleep 1; done
[ -n "$(launchctl getenv CLAUDE_CODE_OAUTH_TOKEN)" ] && echo "launchd environment: token set" || echo "launchd environment: no token"
