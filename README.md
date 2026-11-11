# macos-vms

Disposable macOS VMs for coding agents, driven from the [T3 Code](https://github.com/pingdotgg/t3code) desktop app.

Two macOS VMs run on an Apple Silicon Mac. Each VM is a remote T3 environment with
Claude Code and Codex logged in, a shared Chrome for browser use, and full computer
use. You give an agent a whole Mac to work on, with full access, and nothing of it
touches your own machine. When a VM is in a bad state, `make reset` gives you a clean
one in about a minute, still logged in to Claude Code, Codex and the T3 Code app.

```
 your Mac (client)                 host Mac (Apple Silicon)                VM  mac-vm1, mac-vm2
┌────────────────────┐  SSH tunnel ┌─────────────────────────┐  Softnet   ┌─────────────────────────────┐
│ T3 Code desktop app├────────────▶│ 127.0.0.1:1377N  socat  ├───────────▶│ T3 server             :3773 │
│ browser (voxl)     ├────────────▶│ 127.0.0.1:1690N  socat  ├───────────▶│ voxl screen stream    :6901 │
└────────────────────┘             │                         │            │ Claude Code, Codex          │
                                   │ Tart, launchd           │            │ Chrome (CDP), agent-browser │
                                   └─────────────────────────┘            │ agent-desktop               │
                                                                          └─────────────────────────────┘
```

## What you get

- **A golden image and clones.** `make image` builds one image with all tools and no
  credentials. Every VM is a clone of it, so a clean VM is cheap.
- **T3 without a T3 account.** The T3 server in each VM is reached through an SSH tunnel
  and paired with a one-time code. No T3 Connect, no open ports.
- **Agents that are logged in.** Claude Code uses a long-lived token from your Keychain.
  Codex uses its device login. Both work in T3 threads and survive a VM restart.
- **Browser use.** One persistent Google Chrome per VM, with
  [agent-browser](https://github.com/vercel-labs/agent-browser) attached to it.
- **Computer use.** [agent-desktop](https://github.com/vercel-labs/agent-desktop) drives
  macOS apps through the accessibility tree. The privacy permissions are granted by script.
- **You can watch.** `make view` shows every VM side by side in one browser page,
  streamed by [voxl](https://github.com/tembo/voxl). You see each agent's Chrome and
  desktop and can take over with mouse and keyboard.
- **Network isolation.** With [Softnet](https://github.com/cirruslabs/softnet), a VM
  reaches the internet but not your LAN, your VPN or the other VM.
- **It stays up.** launchd starts the VMs, the T3 servers, Chrome and the tunnel again
  after a restart.

## Requirements

**Host** (the Mac that runs the VMs)

- Apple Silicon, macOS 13 or later, [Homebrew](https://brew.sh)
- Remote Login (SSH) with key-based login from your Mac
- A logged-in desktop session, so turn on automatic login. The VMs run as LaunchAgents
  of that user.
- `sudo` once, to install Softnet. Without passwordless `sudo`, `make host` prints the
  command to run by hand.
- Disk: about 30 GB for the base image, 33 GB for the golden image and 33 GB for each VM
- RAM: each VM gets 6 GB by default. Two VMs on a 16 GB host work, but leave little spare.

**Client** (your Mac)

- The T3 Code desktop app, the same version as `T3_VERSION` in `config.env`
- The Claude Code CLI, for `claude setup-token`
- `python3` (comes with the Xcode Command Line Tools)

**Accounts**

- A Claude plan that includes Claude Code (Pro, Max, Team or Enterprise)
- A ChatGPT plan that includes Codex

Apple's license allows **at most two running macOS VMs per host**. macOS enforces that limit.

## Quick start

```sh
git clone https://github.com/erikmay/macos-vms && cd macos-vms
echo 'VM_HOST=my-mac-mini' > config.local.env   # an SSH destination; see "One Mac only"

make host            # Tart, Softnet and socat on the host
make image           # the golden image; the first run downloads about 27 GB
make up N=1          # VM mac-vm1, its T3 server, the tunnel, and pairing with your T3 Code app

claude setup-token   # prints a long-lived Claude Code token
make token           # stores that token in your Keychain
make auth N=1        # puts the token into the VM, then starts the Codex device login
```

`make up` opens a pairing link in the T3 Code app. After that, `mac-vm1` is in the app's
environment list. For the second VM, run `make up N=2` and `make auth N=2`.

## Commands

Run `make` to see this list. `N` is the VM number, 1 or 2.

| Command | What it does |
| --- | --- |
| `make host` | Prepare the host: Tart, Softnet, socat |
| `make image` | Build the golden image. Needs a free VM slot: `make stop N=2` first if two VMs run |
| `make up N=1` | Create the VM if it is missing, start T3 in it, update the tunnel, pair the app |
| `make token` | Store the token from `claude setup-token` in your Keychain |
| `make auth N=1` | Log in Claude Code and Codex in the VM (`auth-claude`, `auth-codex` do one each) |
| `make status` | VMs, T3 reachability, tool versions, logins |
| `make view` | All VMs side by side in the browser (voxl). `make view N=1` shows one VM |
| `make vnc` | The same in macOS Screen Sharing (login `admin` / `admin`), as a fallback |
| `make pair N=1` | Pair the app again. T3 sessions expire after 30 days |
| `make tunnel` | Reinstall and restart the SSH tunnel on your Mac (also after you change networks) |
| `make update N=1` | Update tools and settings in the VM in place. Logins and data stay |
| `make stop N=1`, `make start N=1` | Stop the VM until you start it again |
| `make reset N=1` | Delete the VM and create a clean one. The logins are kept (see below) |
| `make delete N=1` | Delete the VM. Its logins stay saved for the next VM with this number |
| `make forget N=1` | Delete the saved logins of VM slot N |
| `make bench N=2` | Time three resets of VM N and write a report to `docs/benchmarks/` |

## Configuration

Defaults are in [`config.env`](config.env). Put your values in `config.local.env`, which
git ignores.

| Setting | Default | Meaning |
| --- | --- | --- |
| `VM_HOST` | none, required | SSH destination of the host, or `local` |
| `VM_CPU`, `VM_MEMORY_MB` | `4`, `6144` | Size of each VM |
| `BASE_IMAGE` | `ghcr.io/cirruslabs/macos-tahoe-base:latest` | The image that the golden image starts from |
| `T3_VERSION` | `0.1.8` | T3 server version in the VMs. Keep it equal to your desktop app |
| `TART_RUN_FLAGS` | `--no-graphics --net-softnet` | How Tart runs a VM. Remove `--net-softnet` to give VMs access to private networks |
| `T3_LOCAL_PORT_BASE`, `VOXL_LOCAL_PORT_BASE`, `VNC_LOCAL_PORT_BASE` | `13770`, `16900`, `15900` | Loopback ports on your Mac: VM N uses base + N |
| `VOXL_VERSION` | `0.3.4` | voxl version, built from crates.io in the image |

The agent settings that go into every VM are in [`guest/config/`](guest/config):
Claude Code adds no co-author line to commits and loads no claude.ai connectors, and
Codex loads no ChatGPT connectors. Change these files to your taste before `make image`,
or apply a change to a running VM with `make update`.

### One Mac only

Set `VM_HOST=local` to run the VMs on the Mac you work on. The scripts then run the host
commands directly and install no tunnel, because the forwarders already listen on your
loopback. I use a separate host, so this mode has had less testing.

## Agent logins

No credential is part of the golden image. Each VM gets its logins from `make auth`.

**Claude Code** uses the token from `claude setup-token`, which is valid for about one
year. `make token` stores it in your Keychain and `make auth-claude` copies it into the
VM. The token can only make model requests, so claude.ai connectors and Remote Control do
not work with it. When it expires, make a new one and run `make token` and
`make auth-claude` again. See the
[Claude Code authentication docs](https://code.claude.com/docs/en/authentication).

**Codex** uses `codex login --device-auth`. `make auth-codex` prints a link and a
one-time code, and you approve the code in your browser. Every VM has its own login. Do
not copy a Codex `auth.json` between machines: its refresh token works only once, so the
first machine that refreshes it logs the others out. See the
[Codex authentication docs](https://developers.openai.com/codex/auth).

### Logins survive a reset

A VM number is a slot. Before `make delete` or `make reset` deletes a VM, it saves the
slot's login state in a Keychain item on your Mac (`macos-vms-state-mac-vmN`), and
`make up` puts it into the new VM:

- the Codex login (`~/.codex/auth.json`). It moves from the old VM to its replacement,
  never to a second running machine, so its single-use refresh token stays valid.
- the T3 server identity (environment ID and keys), so the app keeps one entry per slot
- the app's session, so the app reconnects by itself and needs no new pairing

Everything else starts clean: threads, projects, files and the Chrome profile.
`make forget N=…` deletes the saved state; the next VM in that slot then starts without
logins.

### How long a reset takes

`TIMING=1 make reset N=2` prints the time of each step, and `make bench N=2` runs three
resets and writes a report to [docs/benchmarks](docs/benchmarks). On a MacBook Pro M1
(16 GB) host, a reset takes about 70 seconds (median of three runs: 69 s):

| Step | Seconds |
| --- | --- |
| Save the logins, delete the old VM | 5–7 |
| Clone the golden image (an APFS clone), launchd jobs | 2 |
| macOS boots until the Tart guest agent answers | 32–38 |
| Restore the logins, start T3, privacy permissions, app session | 10–12 |
| Tunnel, pairing check | 3–5 |
| Claude token and a test prompt, Codex check | 9 |

The app reconnects to the new VM within about a minute.

## Browser and computer use

The setup follows [tobi/wrapvm](https://github.com/tobi/wrapvm), adapted from a Linux
desktop to macOS:

- A LaunchAgent keeps one Google Chrome open in each VM, with its debugging port on
  `127.0.0.1:9222`. It runs on the VM's real screen, not headless.
- `agent-browser` attaches to that Chrome (`{"headed": true, "autoConnect": true}`), so
  logins and tabs persist between agent runs, and you can watch.
- `agent-desktop` reads and drives macOS apps through the accessibility tree.
- Two small skills, `browser` and `desktop`, are in `~/.agents/skills` and are linked into
  `~/.claude/skills`. They tell the agent to load the guide that each CLI prints, so the
  instructions always match the installed version.

### Watching: voxl

[voxl](https://github.com/tembo/voxl) runs in each VM as a LaunchAgent and streams the
screen as H.264 over one WebSocket; the browser decodes it with WebCodecs. Each VM makes
its own random password at its first start (`~/.config/voxl/password`). `make view` reads
the passwords and writes a page with one pane per VM to
`~/Library/Caches/macos-vms/view.html` (mode 600). A small LaunchAgent on your Mac
(`macos-vms.view`) serves that page on `http://127.0.0.1:16900/`, because Chrome's Local
Network Access protection blocks a `file://` page from loading the streams from
`127.0.0.1`, and `make view` opens it. Each pane has a button
to maximize it; a hidden pane disconnects, so voxl encodes nothing for it.

voxl is built from crates.io inside the image (`cargo install voxl-server`, about two
minutes). Its code is MIT, but the binary links x264 and is therefore GPL-2.0.

### No prompts on the VM screen

Nobody sits at a VM, so the setup keeps macOS dialogs away:

- The privacy permissions (Accessibility, Screen Recording) for the T3 runtime and voxl
  are written into the TCC database before the programs start.
- The "bypass the system private window picker" alert is prevented by a recent
  approval date in replayd's file (see [docs/design.md](docs/design.md)).
- A LaunchAgent (`macos-vms.prompt-guard`) checks every 10 seconds for macOS's
  "Allow … to find devices on local networks?" prompt and answers "Allow", only for T3,
  voxl and Google Chrome, through the accessibility API. It needs the Accessibility
  permission for the `agent-desktop` binary.

## How it works

The interesting parts are the problems that the scripts solve. The details are in
[docs/design.md](docs/design.md).

- T3's background service does not read shell startup files, so the Claude token reaches
  it through `launchctl setenv`.
- Softnet gives a VM a new IP address on every boot, so the port forwarders look the
  address up for each connection.
- macOS gives the Accessibility and Screen Recording permissions to the process that
  starts a tool. For an agent in a T3 thread that is the T3 runtime, so that binary gets
  the permissions.
- Commands run inside a VM through the Tart guest agent (`tart exec`), so the VMs need no
  SSH setup.

## Security

Read this before you give an agent full access.

- **The credentials are in the VM.** An agent in a VM can read the Claude token and the
  Codex login. The VMs have internet access, so an agent that follows a malicious prompt
  can send them out. Softnet protects your network, not these credentials.
- **The base image is built for automation, not for defense.** System Integrity
  Protection is off, the user `admin` has the password `admin` and passwordless `sudo`.
  The scripts use this: they write the privacy permissions into the TCC database.
- **What limits access to a VM:** it has no route from your LAN (Softnet), SSH password
  login is off, the forwarders listen on the host's loopback only, and T3 needs a pairing
  code. voxl needs its own password per VM. Screen Sharing still accepts `admin` / `admin`,
  but only through the host's loopback, so through your SSH login.
- **Softnet runs as SUID root** on the host. That is how Cirrus Labs designed it.
- Do not add `--net-softnet-expose` to `TART_RUN_FLAGS`. It also opens the port on the
  host's LAN address.

### Host in the same local network

The tunnel follows your SSH configuration for `VM_HOST`. If the host is in your local
network but you also reach it through a VPN, make SSH prefer the direct path when it is
available, or every byte of the screen stream and T3 makes a trip through the VPN server.
For example, in `~/.ssh/config` before the host's normal entry:

```
Match originalhost my-mac-mini exec "nc -z -G 1 192.168.1.20 22 >/dev/null 2>&1"
	HostName 192.168.1.20
	HostKeyAlias <the address in known_hosts>
```

In one test setup, this changed SSH throughput from 4 MB/s (through a VPN hub) to 49 MB/s
and the round trip from about 50 ms to about 5 ms. Run `make tunnel` after you change
networks, so the tunnel takes the new path.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `make status` says T3 is not reachable | `make tunnel`. If that does not help, `make update N=…` |
| The app shows the VM as offline after 30 days | `make pair N=…` |
| A T3 thread says "Claude could not authenticate" | `make auth-claude N=…` |
| `agent-desktop permissions` says "denied" after a T3 update | `make update N=…`. The T3 runtime has a new path |
| `make image` says two VMs are running | `make stop N=2`, `make image`, `make start N=2` |
| A new T3 Code version | Set `T3_VERSION` in `config.local.env`, then `make update N=…` and `make image` |
| A VM does not come back | Look at `~/Library/Logs/macos-vms.<vm>.log` on the host |

## Tested with

macOS 27.0 on the host (MacBook Pro M1, 16 GB), macOS 26 "Tahoe" guests, Tart 2.41.1,
Softnet 0.25.0, T3 Code 0.1.8, Claude Code 2.1, Codex CLI 0.167, agent-browser 0.42,
agent-desktop 1.2.

T3 Code is in beta. `t3 up`, `t3 pair` and the `t3code://pair` link can change.

## Credits

- [Tart](https://github.com/cirruslabs/tart) and [Softnet](https://github.com/cirruslabs/softnet)
  by Cirrus Labs. Tart has its own license. Read it before you use it in an organization.
- [tobi/wrapvm](https://github.com/tobi/wrapvm) for the shared Chrome, the skills and the
  idea that a person can watch.
- [voxl](https://github.com/tembo/voxl) by Tembo for the screen stream.
- [BergQuester/XcodeCellmate](https://github.com/BergQuester/XcodeCellmate) and
  [Running AI agents in isolated macOS VMs](https://blog.gertjvr.com/articles/2026/08/running-ai-agents-in-isolated-macos-vms/)
  for the golden-image pattern with Tart.

This project is not affiliated with T3 Tools, Anthropic, OpenAI, Cirrus Labs or Apple.

## License

[MIT](LICENSE)
