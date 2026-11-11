#!/usr/bin/env bash
# Make sure VM N exists and runs: clone it from the golden image if it is missing,
# run it under launchd on the host, and forward its T3 and Screen Sharing ports to
# the host's loopback. Idempotent.
. "$(dirname "$0")/lib.sh"
n="${1:-}"
vm="$(vm_name "$n")"

if ! vm_exists "$vm"; then
  vm_exists "$GOLDEN_IMAGE" || die "no golden image on $VM_HOST. Run: make image"
  log "Cloning $GOLDEN_IMAGE -> $vm"
  host "$TART clone $GOLDEN_IMAGE $vm && $TART set $vm --cpu $VM_CPU --memory $VM_MEMORY_MB"
fi

# launchd starts the VM at login and restarts it when it stops.
# PATH lets Tart find Softnet in /usr/local/bin.
log "Running $vm under launchd on $VM_HOST"
launchd_install host "$LAUNCHD_PREFIX.vm.$vm" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LAUNCHD_PREFIX.vm.$vm</string>
  <key>ProgramArguments</key><array>
    <string>/bin/sh</string><string>-c</string>
    <string>exec "\$HOME/bin/tart" run $TART_RUN_FLAGS $vm &gt;&gt;"\$HOME/Library/Logs/$LAUNCHD_PREFIX.$vm.log" 2&gt;&amp;1</string>
  </array>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
</dict></plist>
PLIST

# Softnet gives the VM a new IP on every boot, so the forwarder looks it up for
# each connection. It listens on the host's loopback only.
forward() { # NAME HOST_PORT GUEST_PORT
  launchd_install host "$LAUNCHD_PREFIX.fwd-$1.$vm" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LAUNCHD_PREFIX.fwd-$1.$vm</string>
  <key>ProgramArguments</key><array>
    <string>/opt/homebrew/bin/socat</string>
    <string>TCP-LISTEN:$2,bind=127.0.0.1,reuseaddr,fork</string>
    <string>SYSTEM:exec /usr/bin/nc \$(\$HOME/bin/tart ip $vm) $3</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
PLIST
}
log "Forwarding ports on $VM_HOST: 127.0.0.1:$(t3_local_port "$n") -> T3, :$(voxl_local_port "$n") -> voxl, :$(vnc_local_port "$n") -> Screen Sharing"
forward t3   "$(t3_local_port "$n")"   "$T3_PORT"
forward voxl "$(voxl_local_port "$n")" "$VOXL_PORT"
forward vnc  "$(vnc_local_port "$n")"  "$VNC_PORT"

log "Waiting for $vm"
vm_wait "$vm"

# T3 shows the computer name as the environment's label.
guest "$vm" "[ \"\$(scutil --get ComputerName)\" = $vm ] || for k in ComputerName LocalHostName HostName; do sudo -n scutil --set \$k $vm; done"

log "$vm is running"
