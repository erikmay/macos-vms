#!/bin/zsh
# Runs inside a VM (login zsh, guest user). Installs or updates the agent CLIs.
# Idempotent. No credentials: they are added per VM by `make auth`.
# Args: <T3 version>
set -euo pipefail
t3_version="$1"

echo "--> Claude Code"
curl -fsSL https://claude.ai/install.sh | bash >/dev/null
grep -q '.local/bin' ~/.zprofile 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
export PATH="$HOME/.local/bin:$PATH"

echo "--> Codex"
npm install -g @openai/codex@latest >/dev/null

echo "--> T3 Code $t3_version"
npm install -g "t3@$t3_version" >/dev/null

# The base image allows SSH logins with its default password. The VMs are managed
# through the Tart guest agent, so password logins are not needed.
echo "--> SSH: no password logins"
sudo -n tee /etc/ssh/sshd_config.d/100-no-password.conf >/dev/null <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
CONF
sudo -n launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true

# Interactive shells read the Claude token from a file that `make auth` writes.
# T3's service gets it through launchd instead (guest/agent-env.sh).
mkdir -p ~/.config/agent-auth && chmod 700 ~/.config/agent-auth
grep -q agent-auth ~/.zshenv 2>/dev/null || cat >> ~/.zshenv <<'ZSH'
if [ -r ~/.config/agent-auth/claude-oauth-token ]; then
  export CLAUDE_CODE_OAUTH_TOKEN="$(<~/.config/agent-auth/claude-oauth-token)"
fi
ZSH

# Default project folder for T3.
mkdir -p ~/work

echo "claude $(claude --version), $(codex --version), $(t3 --version)"
