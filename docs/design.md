# Design notes

Why the scripts do what they do. Most of it comes from problems that only showed up on
a running system.

## Three machines

| Name | What | How the scripts reach it |
| --- | --- | --- |
| client | Your Mac, with the T3 Code app | Runs the scripts |
| host | The Mac that runs the VMs | `ssh $VM_HOST`, or directly with `VM_HOST=local` |
| guest | A macOS VM | `tart exec` on the host (Tart guest agent) |

`scripts/` runs on the client and sends work to the host and the guests. `guest/` holds
the zsh scripts that run inside a VM. They are piped through `tart exec -i <vm> zsh -l -s`,
so a VM needs no SSH keys and no files copied in first.

## launchd jobs

Everything that must survive a restart is a LaunchAgent. All labels start with `macos-vms.`

| Where | Label | Job |
| --- | --- | --- |
| host | `macos-vms.vm.<vm>` | `tart run` for the VM. `KeepAlive`, so a VM that stops is started again |
| host | `macos-vms.fwd-t3.<vm>`, `macos-vms.fwd-vnc.<vm>` | socat forwarders on the host's loopback |
| client | `macos-vms.tunnel` | `ssh -N -L …` to the host |
| guest | `com.t3tools.t3code.service` | The T3 server. Installed by `t3 up`, not by this repo |
| guest | `macos-vms.agent-env` | Exports the Claude token to launchd at login |
| guest | `macos-vms.agent-chrome` | Starts the shared Chrome if it does not run (at login, then every 30 s) |

`scripts/launchd.sh` installs a job only when its plist changed. `make up` and
`make update` are therefore safe to run again: they do not restart a VM that is already
set up.

## Network path

```
T3 Code app ── 127.0.0.1:1377N ──ssh──▶ host 127.0.0.1:1377N ──socat──▶ <VM IP>:3773
```

- **Softnet** (`--net-softnet`) lets a VM reach the internet, but no private address
  ranges. The host can still open connections to the VM.
- **The VM's IP changes on every boot** with Softnet. The forwarder is
  `socat TCP-LISTEN:…,fork SYSTEM:"nc $(tart ip <vm>) <port>"`: it asks Tart for the
  address each time a connection comes in. A fixed address in the tunnel would break
  after the first VM restart.
- **`--net-softnet-expose` is not used.** It would do the forwarding, but it also listens
  on the host's LAN address.
- **The T3 server uses `--lan`** so that it listens on the VM's network interface. The
  host is the only machine that can reach that interface, and a client still needs a
  pairing code.

## Pairing without a T3 account

`t3 pair` in the VM prints a one-time token. The desktop app accepts a link of the form
`t3code://pair?pairingUrl=<url>`. `scripts/pair.sh` builds that link with the tunnel
port (`http://127.0.0.1:1377N/pair#token=…`) and opens it. T3 Connect stays off.

T3 shows the computer name as the environment's label, so `vm-create.sh` sets the
computer name to the VM name.

## The Claude token and T3

`claude setup-token` gives a long-lived token for `CLAUDE_CODE_OAUTH_TOKEN`. Putting it
in `~/.zshenv` makes `claude` work in a shell, but **T3 threads still fail** with "Claude
could not authenticate". T3 runs as a launchd service and does not read shell startup
files, so the agents it starts get launchd's environment.

`guest/agent-env.sh` installs a LaunchAgent that runs at login, calls
`launchctl setenv CLAUDE_CODE_OAUTH_TOKEN …` and restarts the T3 service. The token
itself is in `~/.config/agent-auth/claude-oauth-token` (mode 600) in the VM, and in the
Keychain on the client. It is never in the golden image and never in this repository.

## Codex logins

Each VM runs `codex login --device-auth` once. Copying one `auth.json` to all VMs looks
simpler, but Codex refresh tokens are single-use: the first VM that refreshes the token
logs the others out.

## Privacy permissions for computer use

`agent-desktop` needs Accessibility and Screen Recording. macOS does not give these to
the tool, but to the *responsible process*: the app that started it. In a T3 thread that
is the T3 runtime binary, `~/.t3/runtime/versions/<version>/t3`. From `tart exec` the
permissions look fine, because the Tart guest agent already has them, and then the same
command fails in a T3 thread.

The Cirrus Labs images have System Integrity Protection off, so `guest/tcc-grant.sh`
writes the three grants (Accessibility, Screen Capture, Post Event) for the T3 runtime
into the system TCC database. The path contains the T3 version, so the script must run
again after a T3 update. `make update` does that.

## Golden image

`make image` clones the base image, boots it, runs `scripts/provision.sh` and saves the
result. `make update` runs the same `provision.sh` on a living VM. One provisioning path
serves both, so an updated VM and a new VM do not drift apart.

`tart exec` is used instead of Packer. It keeps the dependency list short, and the same
mechanism provisions the image and manages the VMs later.

Tart is installed from its GitHub release at a pinned version, in `~/opt/tart` with a
link in `~/bin`. The scripts need a known path that also works in launchd jobs.

## The shared Chrome

The LaunchAgent does not run the Chrome binary with `KeepAlive`. That version broke as
soon as a Chrome with the same profile ran outside the job (after a Chrome update, or
opened by hand): each new launch handed over to the running Chrome, which opened one
more window, and exited, so launchd started it again. The VMs collected hundreds of
windows. Now the job runs `~/.config/agent-chrome/start.sh` every 30 seconds, and the
script starts Chrome only when no Chrome with the agent profile runs.

`desktop.sh` also removes the quarantine flag from Chrome. Without that, the first
start waits in the "downloaded from the Internet" dialog, and the debugging port never
opens.
