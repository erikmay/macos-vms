#!/bin/zsh
# Runs inside a VM. Grants Accessibility, Screen Recording and synthetic input to
# the T3 runtime, so agent-desktop works in T3 threads without clicks in System Settings.
# Why the T3 runtime: macOS gives these permissions to the "responsible" process, and
# for an agent started by T3 that is T3's service binary (~/.t3/runtime/versions/<v>/t3).
# This writes to the system TCC database, which works only with SIP off. SIP is off in
# the Cirrus Labs images. Idempotent; run it again after a T3 update (new binary path).
set -euo pipefail
db="/Library/Application Support/com.apple.TCC/TCC.db"

csrutil status | grep -q disabled || { echo "SIP is on: grant the permissions by hand (agent-desktop permissions --guide)" >&2; exit 1; }

clients=( ~/.t3/runtime/versions/*/t3(N) )
[ ${#clients[@]} -gt 0 ] || { echo "no T3 runtime found; start the T3 service first" >&2; exit 1; }

for client in "${clients[@]}"; do
  for service in kTCCServiceAccessibility kTCCServiceScreenCapture kTCCServicePostEvent; do
    # client_type 1 = path, auth_value 2 = allowed
    sudo -n sqlite3 "$db" "INSERT OR REPLACE INTO access
      (service, client, client_type, auth_value, auth_reason, auth_version, flags)
      VALUES ('$service', '$client', 1, 2, 0, 1, NULL);"
  done
  echo "granted: ${client/#$HOME/~}"
done
# tccd caches its decisions.
sudo -n killall tccd 2>/dev/null || true

# On macOS 26, replayd shows a "requesting to bypass the system private window picker"
# alert after a process's first screen capture, even with Screen Recording allowed. It
# reads ScreenCaptureApprovals.plist at its first capture after it starts, and skips the
# alert when the process's kScreenCaptureApprovalLastUsed is recent. Afterwards it keeps
# its own copy and updates that date itself. So: stop replayd (it ignores SIGTERM;
# launchd starts it again on demand), then set the date to now for the processes that
# capture: T3 (agents in threads) and the Tart guest agent (`tart exec`), by real path.
# Undocumented; found by pmwoz/brushes-quicklook#161.
agent="$(readlink -f /opt/homebrew/bin/tart-guest-agent 2>/dev/null || true)"
approvals=~/Library/Group\ Containers/group.com.apple.replayd/ScreenCaptureApprovals
pkill -9 -x replayd 2>/dev/null || true
mkdir -p "${approvals:h}"
now="$(date -u '+%Y-%m-%d %H:%M:%S +0000')"
for client in "${clients[@]}" ${agent:+"$agent"}; do
  defaults write "$approvals" "$client" -dict-add kScreenCaptureApprovalLastUsed -date "$now"
done
echo "screen capture alert off for: ${(j:, :)${clients[@]/#$HOME/~}}${agent:+, $agent}"
