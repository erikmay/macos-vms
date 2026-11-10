#!/bin/zsh
# Runs INSIDE a VM. Merges the base agent settings into the user config. Idempotent.
# Args: <claude-settings.json content (base64)> <codex-config.toml content (base64)>
#   Claude Code: no co-author attribution, claude.ai connectors off.
#   Codex:       ChatGPT connectors ("apps" feature) off.
set -euo pipefail
claude_b64="$1"; codex_b64="$2"

mkdir -p ~/.claude ~/.codex

# Claude Code: shallow-merge base keys over existing settings.json.
BASE="$(print -r -- "$claude_b64" | base64 -D)" node -e '
const fs = require("fs"), p = process.env.HOME + "/.claude/settings.json";
let cur = {}; try { cur = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
const out = { ...cur, ...JSON.parse(process.env.BASE) };
fs.writeFileSync(p, JSON.stringify(out, null, 2) + "\n");
'
echo "claude settings: $(tr -d '\n ' < ~/.claude/settings.json)"

# Codex: add each base [section] key that is missing; keep everything Codex wrote.
cfg=~/.codex/config.toml
touch "$cfg"
section=""
print -r -- "$codex_b64" | base64 -D | while IFS= read -r line; do
  case "$line" in
    "") ;;
    \[*\]) section="$line"
           grep -qxF "$section" "$cfg" || printf '%s\n%s\n' "$section" "$(cat "$cfg")" > "$cfg" ;;
    *) key="${line%%=*}"; key="${key// /}"
       # Base value wins: drop the key inside the section, then add the base line.
       awk -v s="$section" -v k="$key" -v l="$line" '
         /^\[/ { f = ($0 == s) }
         f && $0 ~ "^" k "[ ]*=" { next }
         { print }
         $0 == s { print l }
       ' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg" ;;
  esac
done
echo "codex config: $(awk '/^\[features\]/{f=1;print;next} /^\[/{f=0} f' "$cfg" | tr '\n' ' ')"
