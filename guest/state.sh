#!/bin/zsh
# Runs inside a VM. Moves the state that must survive `make reset` in or out of the
# VM, as a base64 tar:
#   - ~/.codex/auth.json          the Codex login of this VM slot
#   - ~/.t3/userdata/environment-id, ~/.t3/userdata/secrets/
#                                 the T3 server identity, so the T3 Code app keeps
#                                 one entry for the slot
#   - the T3 app sessions (desktop clients, not revoked) as SQL, so the app stays
#     signed in and needs no new pairing
# Everything else (threads, projects, files, browser profile) starts clean.
#   state.sh save            print the state (base64)
#   state.sh restore DATA    unpack it; run before the T3 service starts
#   state.sh sessions        load the unpacked sessions; run after T3 has started
# The script itself arrives on stdin through tart exec, so restore takes its data as an argument.
set -euo pipefail
cd ~
db=.t3/userdata/statev2.sqlite
sessions=.t3/userdata/restore-sessions.sql
case "$1" in
  save)
    if [ -f "$db" ]; then
      sqlite3 "$db" ".mode insert auth_sessions" \
        "select * from auth_sessions where revoked_at is null and client_device_type = 'desktop' and expires_at > strftime('%Y-%m-%dT%H:%M:%fZ','now')" \
        | sed 's/^INSERT INTO/INSERT OR REPLACE INTO/' > "$sessions"
    fi
    files=()
    for f in .codex/auth.json .t3/userdata/environment-id .t3/userdata/secrets "$sessions"; do
      [ -s "$f" ] || [ -d "$f" ] && files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || exit 0
    tar czf - "${files[@]}" | base64
    ;;
  restore)
    umask 077
    print -rn -- "$2" | base64 -D | tar xzf -
    ;;
  sessions)
    [ -s "$sessions" ] || { echo "no saved app sessions"; exit 0; }
    for _ in {1..30}; do sqlite3 "$db" "select 1 from auth_sessions limit 0" 2>/dev/null && break; sleep 1; done
    sqlite3 "$db" < "$sessions"
    echo "restored $(grep -c '^INSERT' "$sessions") app session(s)"
    mv -f "$sessions" "$sessions.done"
    ;;
  *) echo "usage: state.sh save|restore DATA|sessions" >&2; exit 2 ;;
esac
