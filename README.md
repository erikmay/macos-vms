# macos-vms

Disposable macOS VMs for coding agents, driven from the [T3 Code](https://github.com/pingdotgg/t3code) desktop app.

Two macOS VMs run on an Apple Silicon Mac. Each VM is a remote T3 environment with
Claude Code and Codex logged in, a shared Chrome for browser use, and full computer
use. You give an agent a whole Mac to work on, with full access, and nothing of it
touches your own machine. When a VM is in a bad state, `make reset` gives you a clean
one in a few minutes.

```
 your Mac (client)                 host Mac (Apple Silicon)                VM  mac-vm1, mac-vm2
┌────────────────────┐  SSH tunnel ┌─────────────────────────┐  Softnet   ┌─────────────────────────────┐
│ T3 Code desktop app├────────────▶│ 127.0.0.1:1377N  socat  ├───────────▶│ T3 server             :3773 │
│ Screen Sharing     ├────────────▶│ 127.0.0.1:1590N  socat  ├───────────▶│ Screen Sharing        :5900 │
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
- **You can watch.** `make view N=1` opens Screen Sharing into the VM. You see the agent's
  Chrome and desktop and can take over.
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
| `make view N=1` | Screen Sharing into the VM (login `admin` / `admin`) |
| `make pair N=1` | Pair the app again. T3 sessions expire after 30 days |
| `make tunnel` | Reinstall the SSH tunnel on your Mac |
| `make update N=1` | Update tools and settings in the VM in place. Logins and data stay |
| `make stop N=1`, `make start N=1` | Stop the VM until you start it again |
| `make reset N=1` | Delete the VM and create a clean one. Run `make auth` again afterwards |
| `make delete N=1` | Delete the VM |

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
| `T3_LOCAL_PORT_BASE`, `VNC_LOCAL_PORT_BASE` | `13770`, `15900` | Loopback ports on your Mac: VM N uses base + N |

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
  code. Screen Sharing still accepts `admin` / `admin`, but only through the host's
  loopback, so through your SSH login.
- **Softnet runs as SUID root** on the host. That is how Cirrus Labs designed it.
- Do not add `--net-softnet-expose` to `TART_RUN_FLAGS`. It also opens the port on the
  host's LAN address.

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
- [BergQuester/XcodeCellmate](https://github.com/BergQuester/XcodeCellmate) and
  [Running AI agents in isolated macOS VMs](https://blog.gertjvr.com/articles/2026/08/running-ai-agents-in-isolated-macos-vms/)
  for the golden-image pattern with Tart.

This project is not affiliated with T3 Tools, Anthropic, OpenAI, Cirrus Labs or Apple.

## License

[MIT](LICENSE)
