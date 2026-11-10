#!/usr/bin/env bash
# ReddiDotAgents sync: compare (default) or apply this kit's managed settings on this machine.
#
# Managed surfaces, each merged rather than replaced so personal settings survive:
#   omp   ~/.omp/agent/config.yml keys listed in omp/settings.json, merged through
#         `omp config get/set` (record values merge key-by-key; the kit wins per key)
#         ~/.omp/agent/extensions/provider-balancer.ts
#         ~/.omp/agent/AGENTS.md managed block <- shared/fleet-rules.md
#   pi    ~/.pi/agent/settings.json keys from pi/settings.json (deep merge)
#         ~/.pi/agent/AGENTS.md managed block <- shared/fleet-rules.md
#   firstmate  <firstmate-home>/config/crew-dispatch.json (whole file)
#   npm   global CLI tools listed in npm-globals.txt
#   herdr omp and pi integrations (`herdr integration install`)
# Credentials, logins, sessions and auth stores are never read or written.
#
# --check exits 1 when anything drifts, 0 when the machine matches the kit.
# --apply backs up every file it changes under ~/.reddidotagents-backups/<timestamp>/.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sync.sh [--check | --apply] [options]

  --check                 Report drift only (default). Exit 1 on drift.
  --apply                 Apply the kit, backing up every changed file first.
  --firstmate-home DIR    Firstmate home (default: $FIRSTMATE_HOME or ~/firstmate).
  --dispatch NAME         Crew dispatch profile: "default" (Claude, ChatGPT, Antigravity)
                          or "cursor" (Cursor subscription, including Grok through
                          Cursor) for a home whose primary runs in Cursor or Grok.
  --upgrade-npm           With --apply, also reinstall listed npm tools at @latest.
  --skip-npm              Do not check or install npm global tools.
  --skip-herdr            Do not check or install herdr integrations.
  --skip-pi               Do not manage Pi settings or rules.
  -h, --help              Show this help.

Environment: REDDIDOTAGENTS_PI_DIR overrides the Pi agent dir (default ~/.pi/agent);
the omp agent dir is whatever `omp config path` reports (PI_CODING_AGENT_DIR
or --profile select another one).
EOF
}

MODE=check
FM_HOME=${FIRSTMATE_HOME:-$HOME/firstmate}
DO_NPM=1 DO_HERDR=1 DO_PI=1 UPGRADE_NPM=0
DISPATCH=default
while [ $# -gt 0 ]; do
  case "$1" in
  --check) MODE=check ;;
  --apply) MODE=apply ;;
  --firstmate-home) FM_HOME=${2:?--firstmate-home needs a directory}; shift ;;
  --dispatch) DISPATCH=${2:?--dispatch needs a profile name}; shift ;;
  --upgrade-npm) UPGRADE_NPM=1 ;;
  --skip-npm) DO_NPM=0 ;;
  --skip-herdr) DO_HERDR=0 ;;
  --skip-pi) DO_PI=0 ;;
  -h | --help) usage; exit 0 ;;
  *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
case "$DISPATCH" in
default) DISPATCH_FILE=$ROOT/firstmate/crew-dispatch.json ;;
cursor) DISPATCH_FILE=$ROOT/firstmate/crew-dispatch.cursor.json ;;
*) echo "unknown --dispatch profile: $DISPATCH (use default or cursor)" >&2; exit 2 ;;
esac
BACKUP_DIR=${REDDIDOTAGENTS_BACKUP_DIR:-$HOME/.reddidotagents-backups}/$(date +%Y%m%d-%H%M%S)
BLOCK_BEGIN='<!-- reddidotagents:begin (managed by ReddiDotAgents; edit the ReddiDotAgents repo, not this block) -->'
BLOCK_END='<!-- reddidotagents:end -->'
DRIFT=0 MISSING=0

section() { printf '\n== %s\n' "$1"; }
ok() { printf '  ok      %s\n' "$1"; }
drift() { DRIFT=1; printf '  DRIFT   %s\n' "$1"; }
missing() { MISSING=1; printf '  MISSING %s\n' "$1"; }
wrote() { printf '  applied %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

backup() { # <file>: copy to the backup tree once per run, keeping its absolute path
  [ -e "$1" ] || return 0
  local dest="$BACKUP_DIR/${1#/}"
  [ -e "$dest" ] && return 0
  mkdir -p "$(dirname "$dest")"
  cp -p "$1" "$dest"
}

sync_file() { # <src> <dest> <label>
  if [ -f "$2" ] && cmp -s "$1" "$2"; then ok "$3"; return 0; fi
  drift "$3 ($2)"
  [ "$MODE" = apply ] || return 0
  backup "$2"
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
  wrote "$2"
}

managed_block() { # <src-md> <dest-md> <label>: replace or append the marked block, keep the rest
  local current='' next
  [ -f "$2" ] && current=$(cat "$2")
  if printf '%s' "$current" | grep -qF "$BLOCK_BEGIN"; then
    next=$(BEGIN="$BLOCK_BEGIN" END="$BLOCK_END" BODY="$(cat "$1")" awk '
      $0 == ENVIRON["BEGIN"] { print; print ENVIRON["BODY"]; skip = 1; next }
      $0 == ENVIRON["END"] { skip = 0 }
      !skip { print }' <<<"$current")
  elif [ -n "$current" ]; then
    next=$(printf '%s\n\n%s\n%s\n%s' "$current" "$BLOCK_BEGIN" "$(cat "$1")" "$BLOCK_END")
  else
    next=$(printf '%s\n%s\n%s' "$BLOCK_BEGIN" "$(cat "$1")" "$BLOCK_END")
  fi
  if [ "$next" = "$current" ]; then ok "$3"; return 0; fi
  drift "$3 ($2)"
  [ "$MODE" = apply ] || return 0
  backup "$2"
  mkdir -p "$(dirname "$2")"
  printf '%s\n' "$next" >"$2"
  wrote "$2"
}

sync_omp() {
  section "omp"
  if ! have omp; then missing "omp is not on PATH (see README prerequisites)"; return 0; fi
  local dir key want cur merged arg backed=0
  dir=$(omp config path)
  for key in $(jq -r 'keys[]' "$ROOT/omp/settings.json"); do
    want=$(jq -c --arg k "$key" '.[$k]' "$ROOT/omp/settings.json")
    cur=$(omp config get "$key" --json 2>/dev/null | jq -c '.value' 2>/dev/null) || cur=null
    [ -n "$cur" ] || cur=null
    merged=$(jq -cn --argjson c "$cur" --argjson w "$want" \
      'if ($w | type) == "object" then (if ($c | type) == "object" then $c else {} end) * $w else $w end')
    if [ "$(jq -cS . <<<"$merged")" = "$(jq -cS . <<<"$cur")" ]; then ok "config $key"; continue; fi
    drift "config $key"
    [ "$MODE" = apply ] || continue
    [ "$backed" = 1 ] || { backup "$dir/config.yml"; backed=1; }
    arg=$(jq -r 'if type == "string" then . else tojson end' <<<"$merged")
    omp config set "$key" "$arg" >/dev/null
    wrote "config $key"
  done
  sync_file "$ROOT/omp/extensions/provider-balancer.ts" "$dir/extensions/provider-balancer.ts" "extension provider-balancer.ts"
  managed_block "$ROOT/shared/fleet-rules.md" "$dir/AGENTS.md" "fleet rules in AGENTS.md"
}

sync_pi() {
  section "pi"
  [ "$DO_PI" = 1 ] || { ok "skipped (--skip-pi)"; return 0; }
  local dir=${REDDIDOTAGENTS_PI_DIR:-$HOME/.pi/agent} file cur merged
  if ! have pi && [ ! -d "$dir" ]; then ok "pi not installed; skipped"; return 0; fi
  file="$dir/settings.json"
  cur='{}'
  [ -f "$file" ] && cur=$(jq -c . "$file")
  merged=$(jq -c --slurpfile w "$ROOT/pi/settings.json" '. * $w[0]' <<<"$cur")
  if [ "$(jq -cS . <<<"$merged")" = "$(jq -cS . <<<"$cur")" ]; then
    ok "settings.json"
  else
    drift "settings.json ($file)"
    if [ "$MODE" = apply ]; then
      backup "$file"
      mkdir -p "$dir"
      jq . <<<"$merged" >"$file"
      wrote "$file"
    fi
  fi
  managed_block "$ROOT/shared/fleet-rules.md" "$dir/AGENTS.md" "fleet rules in AGENTS.md"
}

sync_firstmate() {
  section "firstmate"
  if [ ! -d "$FM_HOME/.git" ] && [ ! -f "$FM_HOME/.git" ]; then
    ok "no Firstmate home at $FM_HOME; skipped (see README to set one up)"
    return 0
  fi
  # The profile names omp roles with effort "auto"; Firstmate before nissan/firstmate#52
  # rejects that, and an invalid dispatch file disables every rule, so never install it there.
  if ! grep -qF '"xhigh","max","auto"' "$FM_HOME/bin/fm-bootstrap.sh" 2>/dev/null; then
    missing "config/crew-dispatch.json: $FM_HOME predates omp auto effort (needs nissan/firstmate#52); update it, then rerun"
    return 0
  fi
  sync_file "$DISPATCH_FILE" "$FM_HOME/config/crew-dispatch.json" "config/crew-dispatch.json ($DISPATCH profile)"
}

sync_npm() {
  section "npm global tools"
  [ "$DO_NPM" = 1 ] || { ok "skipped (--skip-npm)"; return 0; }
  if ! have npm; then missing "npm is not on PATH"; return 0; fi
  local installed pkg todo=()
  installed=$(npm ls -g --depth=0 --json 2>/dev/null | jq -r '.dependencies // {} | keys[]')
  while IFS= read -r pkg; do
    case "$pkg" in '' | '#'*) continue ;; esac
    if grep -qxF "$pkg" <<<"$installed"; then
      ok "$pkg"
      [ "$UPGRADE_NPM" = 1 ] && todo+=("$pkg@latest")
    else
      drift "$pkg not installed globally"
      todo+=("$pkg@latest")
    fi
  done <"$ROOT/npm-globals.txt"
  if [ "$MODE" = apply ] && [ ${#todo[@]} -gt 0 ]; then
    npm install -g "${todo[@]}" >/dev/null
    wrote "npm install -g ${todo[*]}"
  fi
}

sync_herdr() {
  section "herdr integrations"
  [ "$DO_HERDR" = 1 ] || { ok "skipped (--skip-herdr)"; return 0; }
  if ! have herdr; then ok "herdr not installed; skipped"; return 0; fi
  local status name
  status=$(herdr integration status 2>/dev/null || true)
  for name in omp pi; do
    have "$name" || continue
    if grep -qE "^$name: current" <<<"$status"; then ok "$name integration"; continue; fi
    drift "$name integration ($(grep -E "^$name:" <<<"$status" | cut -d'(' -f1 | sed 's/^[^:]*: //' || echo unknown))"
    [ "$MODE" = apply ] || continue
    herdr integration install "$name" >/dev/null
    wrote "herdr integration install $name"
  done
}

if ! have jq; then echo "jq is required (install it, then rerun)" >&2; exit 2; fi
printf 'ReddiDotAgents %s (%s)\n' "$MODE" "$ROOT"
sync_omp
sync_pi
sync_firstmate
sync_npm
sync_herdr

printf '\n'
if [ "$MODE" = apply ]; then
  [ -d "$BACKUP_DIR" ] && printf 'Backups of changed files: %s\n' "$BACKUP_DIR"
  printf 'Applied. Run scripts/sync.sh --check to confirm.\n'
  [ "$MISSING" = 0 ] || printf 'Some prerequisites are missing; see MISSING lines above.\n'
  exit 0
fi
if [ "$DRIFT" = 0 ] && [ "$MISSING" = 0 ]; then
  printf 'In sync.\n'
  exit 0
fi
printf 'Drift found. Review it, then run scripts/sync.sh --apply.\n'
exit 1
