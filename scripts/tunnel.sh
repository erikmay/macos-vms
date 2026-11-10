#!/usr/bin/env bash
# Keep an SSH tunnel from this Mac to the host open (LaunchAgent). For every VM N it
# forwards 127.0.0.1:1377N (T3) and 127.0.0.1:1590N (Screen Sharing) to the same
# ports on the host's loopback, where the forwarders of vm-create.sh listen.
# Run it again after you add or delete a VM.
. "$(dirname "$0")/lib.sh"
label="$LAUNCHD_PREFIX.tunnel"

if is_local_host; then
  launchd_remove client "$label"
  log "VM_HOST=local: the forwarders already listen on this Mac, no tunnel needed"
  exit 0
fi

forwards=""
for vm in $(vm_list); do
  n="${vm#"$VM_PREFIX"}"
  for port in "$(t3_local_port "$n")" "$(vnc_local_port "$n")"; do
    forwards="$forwards<string>-L</string><string>127.0.0.1:$port:127.0.0.1:$port</string>"
  done
  log "$vm: T3 on 127.0.0.1:$(t3_local_port "$n"), Screen Sharing on 127.0.0.1:$(vnc_local_port "$n")"
done
if [ -z "$forwards" ]; then
  launchd_remove client "$label"
  log "No VMs on $VM_HOST: tunnel removed"
  exit 0
fi

launchd_install client "$label" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/ssh</string><string>-N</string>
    <string>-o</string><string>BatchMode=yes</string>
    <string>-o</string><string>ExitOnForwardFailure=yes</string>
    <string>-o</string><string>ServerAliveInterval=15</string>
    <string>-o</string><string>ServerAliveCountMax=3</string>
    $forwards
    <string>$VM_HOST</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardErrorPath</key><string>/tmp/$label.log</string>
</dict></plist>
PLIST

# Wait until the first forward answers.
first="$(t3_local_port "$(vm_list | head -1 | sed "s/^$VM_PREFIX//")")"
for _ in $(seq 1 15); do
  if nc -z 127.0.0.1 "$first" 2>/dev/null; then exit 0; fi
  sleep 1
done
die "the tunnel does not come up; see /tmp/$label.log"
