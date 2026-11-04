#!/usr/bin/env bash
# ReddiDotAgents sync: compare (default) or apply this kit's managed settings on this machine.
#
# Managed surfaces, each merged rather than replaced so personal settings survive:
#   omp   ~/.omp/agent/config.yml keys listed in omp/settings.json, merged through
#         `omp config get/set` (record values merge key-by-key; the kit wins per key;
#         the cheap/mid/high tier lists are the kit's entries plus those in local.json)
#         ~/.omp/agent/extensions/provider-balancer.ts
#         ~/.omp/agent/AGENTS.md managed block <- shared/fleet-rules.md
#   pi    ~/.pi/agent/settings.json keys from pi/settings.json (deep merge)
#         ~/.pi/agent/AGENTS.md managed block <- shared/fleet-rules.md
#   firstmate  <firstmate-home>/config/crew-dispatch.json: the kit's rules and default
#         lanes plus the lanes and rules declared in local.json
#   npm   global CLI tools listed in npm-globals.txt
#   herdr omp and pi integrations (`herdr integration install`)
# Machine-local additions live in local.json next to this kit (git-ignored; see README).
# Without that file, a machine whose tier lists or dispatch file carry entries the kit
# does not define is reported and --apply stops before changing anything.
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
  --upgrade-npm           With --apply, also reinstall listed npm tools at @latest.
  --skip-npm              Do not check or install npm global tools.
  --skip-herdr            Do not check or install herdr integrations.
  --skip-pi               Do not manage Pi settings or rules.
  -h, --help              Show this help.

Environment: REDDIDOTAGENTS_PI_DIR overrides the Pi agent dir (default ~/.pi/agent);
REDDIDOTAGENTS_LOCAL overrides the machine-local additions file (default
<kit>/local.json); the omp agent dir is whatever `omp config path` reports
(PI_CODING_AGENT_DIR or --profile select another one).
EOF
}

MODE=check
FM_HOME=${FIRSTMATE_HOME:-$HOME/firstmate}
DO_NPM=1 DO_HERDR=1 DO_PI=1 UPGRADE_NPM=0
while [ $# -gt 0 ]; do
  case "$1" in
  --check) MODE=check ;;
  --apply) MODE=apply ;;
  --firstmate-home) FM_HOME=${2:?--firstmate-home needs a directory}; shift ;;
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
BACKUP_DIR=${REDDIDOTAGENTS_BACKUP_DIR:-$HOME/.reddidotagents-backups}/$(date +%Y%m%d-%H%M%S)
BLOCK_BEGIN='<!-- reddidotagents:begin (managed by ReddiDotAgents; edit the ReddiDotAgents repo, not this block) -->'
BLOCK_END='<!-- reddidotagents:end -->'
LOCAL_FILE=${REDDIDOTAGENTS_LOCAL:-$ROOT/local.json}
LOCAL='{}' HAVE_LOCAL=0
DRIFT=0 MISSING=0 GUARDED=0

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

load_local() { # read and validate local.json when present
  [ -f "$LOCAL_FILE" ] || return 0
  LOCAL=$(jq -c . "$LOCAL_FILE" 2>/dev/null) || { echo "$LOCAL_FILE is not valid JSON" >&2; exit 2; }
  HAVE_LOCAL=1
  local err
  err=$(jq -rn --argjson l "$LOCAL" --slurpfile f "$ROOT/firstmate/crew-dispatch.json" '
    def nonempty: type == "string" and length > 0;
    def profile_bad:
      type != "object" or (.harness | nonempty | not)
      or (has("model") and (.model | nonempty | not))
      or (has("effort") and (.effort | nonempty | not))
      or (.harness == "omp" and (
           (.provider | nonempty | not)
           or (has("effort") and (.effort as $e | ["low", "medium", "high", "xhigh", "max", "auto"] | index($e)) == null)));
    def profile_id: [.harness, (.model // null), (.effort // null)];
    def rule_bad:
      type != "object" or (.when | nonempty | not)
      or (.use | type) != "array" or (.use | length) == 0 or any(.use[]; profile_bad)
      or (has("select") and .select != "quota-balanced")
      or ((.use | map(profile_id) | length) != (.use | map(profile_id) | unique | length));
    ($f[0].rules | map(.tier)) as $tiers
    | if ($l | type) != "object" then "must be a JSON object"
      elif ($l | has("omp")) and ($l.omp | type) != "object" then "omp must be an object"
      elif ([($l.omp // {}) | keys[] | select(. != "modelRoles")] | length) > 0 then "omp keys must be modelRoles"
      elif (($l.omp // {}) | has("modelRoles")) and ($l.omp.modelRoles | type) != "object" then "omp.modelRoles must be an object"
      elif ([($l.omp.modelRoles // {}) | to_entries[] | select((.key == "cheap" or .key == "mid" or .key == "high") and (.value | type) != "string")] | length) > 0 then
        "omp.modelRoles cheap, mid, and high must be strings"
      elif ($l | has("firstmate")) and ($l.firstmate | type) != "object" then "firstmate must be an object"
      elif ([($l.firstmate // {}) | keys[] | select(. != "use" and . != "rules" and . != "default")] | length) > 0 then
        "firstmate keys must be use, rules, or default"
      elif (($l.firstmate // {}) | has("use")) and ($l.firstmate.use | type) != "object" then "firstmate.use must be an object keyed by tier"
      elif ([($l.firstmate.use // {}) | keys[] | select(. as $t | $tiers | index($t) | not)] | length) > 0 then
        "firstmate.use tiers must be among: \($tiers | join(", "))"
      elif ([($l.firstmate.use // {})[] | select(type != "array")] | length) > 0 then "firstmate.use.<tier> must be an array of profiles"
      elif (($l.firstmate // {}) | has("rules")) and ($l.firstmate.rules | type) != "array" then "firstmate.rules must be an array of rules"
      elif (($l.firstmate // {}) | has("default")) and ($l.firstmate.default | type) != "array" then "firstmate.default must be an array of profiles"
      elif ([($l.firstmate.use // {})[][] | select(profile_bad)] | length) > 0 then "each firstmate.use.<tier> profile must be an object with a non-empty harness; model and effort non-empty when present; omp lanes need a provider and an effort among low, medium, high, xhigh, max, auto"
      elif ([($l.firstmate.default // [])[] | select(profile_bad)] | length) > 0 then "each firstmate.default profile must be an object with a non-empty harness; model and effort non-empty when present; omp lanes need a provider and an effort among low, medium, high, xhigh, max, auto"
      elif ([($l.firstmate.rules // [])[] | select(rule_bad)] | length) > 0 then
        "each firstmate.rules entry must be an object with a non-empty when, a non-empty use array of valid profiles with no repeated harness, model, effort, and select quota-balanced when present"
      else empty
      end')
  [ -z "$err" ] || { echo "$LOCAL_FILE: $err" >&2; exit 2; }
}

omp_get() { # <key>: current value as JSON, null when unset
  local cur
  cur=$(omp config get "$1" --json 2>/dev/null | jq -c '.value' 2>/dev/null) || cur=null
  [ -n "$cur" ] || cur=null
  printf '%s' "$cur"
}

fm_ready() { # $FM_HOME is a Firstmate checkout that accepts omp auto effort (nissan/firstmate#52)
  { [ -d "$FM_HOME/.git" ] || [ -f "$FM_HOME/.git" ]; } && grep -qF '"xhigh","max","auto"' "$FM_HOME/bin/fm-bootstrap.sh" 2>/dev/null
}

undeclared_entries() { # one line per machine entry the kit does not define
  if have omp; then
    jq -rn --argjson c "$(omp_get modelRoles)" --slurpfile k "$ROOT/omp/settings.json" '
      def items: split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0));
      $k[0].modelRoles as $w
      | if ($c | type) == "object" then
          ("cheap", "mid", "high") as $t
          | select(($c[$t] | type) == "string" and ($w[$t] | type) == "string")
          | (($c[$t] | items) - ($w[$t] | items)) as $x
          | select(($x | length) > 0)
          | "omp modelRoles \($t): \($x | join(", "))"
        else empty end'
  fi
  fm_ready && [ -f "$FM_HOME/config/crew-dispatch.json" ] || return 0
  jq -r --slurpfile k "$ROOT/firstmate/crew-dispatch.json" '
    def ukey: "\(.harness // ""):\(.model // "")";
    def lanes: if type == "array" then map(select(type == "object") | ukey) elif type == "object" then [ukey] else [] end;
    $k[0] as $w
    | if type != "object" then empty else
        ((keys - ($w | keys)) as $x | select(($x | length) > 0)
          | "firstmate crew-dispatch.json keys the kit does not write: \($x | join(", ")) (local.json cannot declare these: drop them or add them to the kit)"),
        ((if (.rules | type) == "array" then .rules else [] end) | to_entries[] | .key as $i | .value as $r
          | ($w.rules | map(select(.when == ($r | if type == "object" then .when else null end))) | first) as $kr
          | if $kr != null then
              (($r.use | lanes) - ($kr.use | lanes)) as $x
              | select(($x | length) > 0)
              | "firstmate rule \($kr.tier) lanes: \($x | join(", "))"
            else "firstmate rule \($i + 1): \($r | if type == "object" then (.when // "" | tostring | .[0:60]) else tostring end)" end),
        (((.default | lanes) - ($w.default | lanes)) as $x | select(($x | length) > 0) | "firstmate default lanes: \($x | join(", "))")
      end' "$FM_HOME/config/crew-dispatch.json" 2>/dev/null || true
}

local_guard() { # without local.json, stop on entries the kit does not define instead of dropping them
  [ "$HAVE_LOCAL" = 0 ] || return 0
  local entries line
  entries=$(undeclared_entries)
  [ -n "$entries" ] || return 0
  GUARDED=1
  section "machine-local entries"
  while IFS= read -r line; do missing "$line"; done <<<"$entries"
  printf '  These are neither in the kit nor declared in %s.\n' "$LOCAL_FILE"
  printf '  Keep lanes and rules: declare them in that file (README, "Machine-local additions").\n'
  printf '  Let the kit drop them: create that file containing only {}.\n'
  [ "$MODE" = apply ] || return 0
  printf '\nNothing was changed.\n'
  exit 2
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
    cur=$(omp_get "$key")
    merged=$(jq -cn --arg k "$key" --argjson c "$cur" --argjson w "$want" --argjson l "$(jq -c --arg k "$key" 'if $k == "modelRoles" then .omp.modelRoles // {} else {} end' <<<"$LOCAL")" '
      def items: split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0));
      if ($w | type) == "object" then
        (if ($c | type) == "object" then $c else {} end) as $co
        | ($co * $l * $w) as $base
        | if $k == "modelRoles" then
            reduce ("cheap", "mid", "high") as $t ($base;
              if ($w[$t] | type) == "string" then
                ($w[$t] | items) as $wi
                | (if ($l[$t] | type) == "string" then ($l[$t] | items) else [] end) as $li
                | .[$t] = (($wi + ($li - $wi)) | join(", "))
              else
                .
              end
            )
          else
            $base
          end
      else
        $w
      end')
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
  if ! fm_ready; then
    missing "config/crew-dispatch.json: $FM_HOME predates omp auto effort (needs nissan/firstmate#52); update it, then rerun"
    return 0
  fi
  local file="$FM_HOME/config/crew-dispatch.json" cur='{}' merged
  if [ -f "$file" ]; then
    cur=$(jq -c . "$file" 2>/dev/null) || cur='{}'
  fi
  merged=$(jq -cn --argjson l "$(jq -c '.firstmate // {}' <<<"$LOCAL")" --slurpfile w "$ROOT/firstmate/crew-dispatch.json" '
    def profile_id: [.harness, (.model // null), (.effort // null)];
    def first_per_profile: reduce .[] as $p ([]; if any(.[]; profile_id == ($p | profile_id)) then . else . + [$p] end);
    $w[0] as $kit
    | ($l.use // {}) as $use
    | $kit * {
        rules: ([$kit.rules[] | .use = ((.use + ($use[.tier // ""] // [])) | first_per_profile)] + ($l.rules // [])),
        default: (($kit.default + ($l.default // [])) | first_per_profile)
      }')
  if [ -f "$file" ] && [ "$(jq -cS . <<<"$merged")" = "$(jq -cS . <<<"$cur")" ]; then
    ok "config/crew-dispatch.json"
    return 0
  fi
  drift "config/crew-dispatch.json ($file)"
  [ "$MODE" = apply ] || return 0
  backup "$file"
  mkdir -p "$(dirname "$file")"
  jq . <<<"$merged" >"$file"
  wrote "$file"
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
load_local
local_guard
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
if [ "$GUARDED" = 1 ]; then
  printf 'Drift found. scripts/sync.sh --apply will stop until the machine-local entries above are declared in %s or that file exists with only {}.\n' "$LOCAL_FILE"
else
  printf 'Drift found. Review it, then run scripts/sync.sh --apply.\n'
fi
exit 1
