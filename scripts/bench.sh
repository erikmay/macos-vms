#!/usr/bin/env bash
# Benchmark `make reset` for VM N: run it RUNS times, time each step, and print a
# Markdown report with the host, the step times and the resource use.
# Usage: bench.sh N [RUNS] [OUT_FILE]   (also writes OUT_FILE when given)
# Each run deletes VM N and creates it again; its logins are kept (vm-state.sh).
. "$(dirname "$0")/lib.sh"
n="${1:-}"
vm="$(vm_name "$n")"
runs="${2:-3}"
out="${3:-}"
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || die "RUNS must be a positive number"
vm_exists "$vm" || die "$vm does not exist; create it first: make up N=$n"

# Step = from the first log line that matches its start marker to the next step's.
steps=(
  "Save the logins, delete the old VM|Saved the logins|No saved|is not running|Deleting"
  "Clone the golden image, launchd jobs|Cloning|Running .* under launchd"
  "macOS boots until the Tart guest agent answers|Waiting for"
  "Restore logins, start T3, privacy permissions, app session|is running"
  "Tunnel, pairing check|T3 on 127.0.0.1"
  "Claude token and test prompt, Codex check|Claude token"
)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for run in $(seq 1 "$runs"); do
  log "Run $run of $runs: make reset N=$n"
  start=$(date +%s)
  # TIMING_T0 is set here, so every script of the run counts from the same start.
  TIMING=1 TIMING_T0="$start" make -s -C "$ROOT" reset N="$n" 2>&1 \
    | sed -E 's/\x1b\[[0-9;]*m//g' > "$tmp/run$run.log" \
    || { cat "$tmp/run$run.log" >&2; die "run $run failed"; }
  echo "$(( $(date +%s) - start ))" > "$tmp/run$run.total"
done

# Seconds at which each step starts in one run's log (first matching "==> [Ns]" line).
step_starts() {
  local logf="$1" s pattern t
  for s in "${steps[@]}"; do
    pattern="${s#*|}"
    t="$(grep -E "^==> \[[0-9]+s\] .*(${pattern})" "$logf" | head -1 | sed -E 's/^==> \[([0-9]+)s\].*/\1/')"
    echo "${t:-}"
  done
}

host_info="$(host_script <<'EOF'
model="$(sysctl -n hw.model)"; chip="$(sysctl -n machdep.cpu.brand_string)"
ram="$(( $(sysctl -n hw.memsize) / 1073741824 ))"
echo "$chip ($model), $ram GB RAM, $(sysctl -n hw.ncpu) cores, macOS $(sw_vers -productVersion), Tart $("$HOME/bin/tart" --version)"
EOF
)"

{
  echo "# Reset benchmark"
  echo
  echo "- Date: $(date -u +%Y-%m-%d)"
  echo "- Host: $host_info"
  echo "- VM: $VM_CPU vCPUs, $VM_MEMORY_MB MB RAM, \`$TART_RUN_FLAGS\`, golden image from \`$BASE_IMAGE\`"
  echo "- Command: \`make reset N=$n\`, $runs runs; the other VM kept running"
  echo
  printf '| Step |'; for r in $(seq 1 "$runs"); do printf ' Run %s |' "$r"; done; printf ' Median |\n'
  printf '| --- |'; for _ in $(seq 1 "$runs"); do printf ' ---: |'; done; printf ' ---: |\n'

  for r in $(seq 1 "$runs"); do step_starts "$tmp/run$r.log" > "$tmp/run$r.starts"; done
  i=0
  for s in "${steps[@]}"; do
    i=$((i + 1))
    printf '| %s |' "${s%%|*}"
    vals=()
    for r in $(seq 1 "$runs"); do
      a="$(sed -n "${i}p" "$tmp/run$r.starts")"
      b="$(sed -n "$((i + 1))p" "$tmp/run$r.starts")"
      [ -n "$b" ] || b="$(cat "$tmp/run$r.total")"
      if [ -n "$a" ]; then d=$((b - a)); vals+=("$d"); printf ' %s s |' "$d"; else printf ' – |'; fi
    done
    if [ ${#vals[@]} -gt 0 ]; then
      printf ' %s s |\n' "$(printf '%s\n' "${vals[@]}" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')"
    else
      printf ' – |\n'
    fi
  done
  printf '| **Total** |'
  totals=()
  for r in $(seq 1 "$runs"); do t="$(cat "$tmp/run$r.total")"; totals+=("$t"); printf ' **%s s** |' "$t"; done
  printf ' **%s s** |\n' "$(printf '%s\n' "${totals[@]}" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')"

  echo
  echo "## Resources after the runs"
  echo
  echo "| VM | State | Disk (allocated) |"
  echo "| --- | --- | ---: |"
  host_script "$VM_PREFIX" "$GOLDEN_IMAGE" <<'EOF'
prefix="$1"; golden="$2"
for d in "$HOME/.tart/vms/"*; do
  name="$(basename "$d")"
  case "$name" in "$prefix"[0-9]|"$golden") ;; *) continue ;; esac
  if pgrep -f "tart run .* $name\$" >/dev/null; then state=running; else state=stopped; fi
  echo "| $name | $state | $(du -sh "$d" | cut -f1 | tr -d ' ')B |"
done
echo
echo "\`du\` counts blocks that APFS clones share with the golden image once for every VM,"
echo "so the real disk use is lower than the sum."
echo
# The guest memory belongs to Virtualization.framework's VM processes, not to tart.
vmram="$(ps -axo rss=,comm= | awk '/Virtualization.VirtualMachine/ {s+=$1; n++} END {printf "%d VM processes, %.1f GB resident", n, s/1048576}')"
echo "- Host memory used by the running VMs: $vmram"
echo "- Host memory free: $(memory_pressure | awk -F': ' '/free percentage/ {print $2}')"
echo "- Base image cache (\`~/.tart/cache\`): $(du -sh "$HOME/.tart/cache" 2>/dev/null | cut -f1 | tr -d ' ')B"
EOF
} | tee "${out:-/dev/null}"
if [ -n "$out" ]; then log "Report written to $out"; fi
