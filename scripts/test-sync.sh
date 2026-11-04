#!/usr/bin/env bash
# Behavioural tests for scripts/sync.sh, run against throwaway directories only.
# A stand-in `omp` on PATH implements the `omp config path|get|set` contract the
# sync relies on (get prints {"key","value"}; set takes the value as JSON or a
# string) and keeps its config as JSON in config.yml, the file the sync backs up.
# A stub Firstmate home carries the nissan/firstmate#52 marker.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
FAILS=0 CASES=0

fail() { FAILS=$((FAILS + 1)); printf 'FAIL %s\n' "$1"; }
pass() { printf 'ok   %s\n' "$1"; }
check() { # <label> <expected> <actual>
  CASES=$((CASES + 1))
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '     expected: %s\n     actual:   %s\n' "$2" "$3"; fi
}

mkdir -p "$S/bin"
cat >"$S/bin/omp" <<'SHIM'
#!/usr/bin/env bash
set -eu
f="$FAKE_OMP_DIR/config.yml"
[ -f "$f" ] || printf '{}' >"$f"
case "${1-} ${2-}" in
"config path") printf '%s\n' "$FAKE_OMP_DIR" ;;
"config get") jq -c --arg k "$3" '{key: $k, value: .[$k]}' "$f" ;;
"config set") jq --arg k "$3" --arg v "$4" '.[$k] = ($v | try fromjson catch $v)' "$f" >"$f.tmp" && mv "$f.tmp" "$f" ;;
*) echo "stand-in omp: unsupported arguments: $*" >&2; exit 1 ;;
esac
SHIM
chmod +x "$S/bin/omp"

new_kit() { # <dir>: a copy of this kit that a case may edit
  mkdir -p "$1/scripts"
  cp "$ROOT/scripts/sync.sh" "$1/scripts/"
  cp -R "$ROOT/omp" "$ROOT/firstmate" "$ROOT/shared" "$ROOT/pi" "$ROOT/npm-globals.txt" "$1/"
}

new_machine() { # <dir>: empty omp config, Firstmate home that accepts auto effort
  mkdir -p "$1/omp" "$1/fm/bin" "$1/fm/config"
  : >"$1/fm/.git"
  printf '%s\n' 'EFFORTS=("low","medium","high","xhigh","max","auto")' >"$1/fm/bin/fm-bootstrap.sh"
}

run_sync() { # <kit> <machine> <local.json path> <mode>: output in $OUT, exit status in $RC
  RC=0
  PATH="$S/bin:$PATH" FAKE_OMP_DIR="$2/omp" REDDIDOTAGENTS_LOCAL="$3" REDDIDOTAGENTS_PI_DIR="$2/pi" \
    REDDIDOTAGENTS_BACKUP_DIR="$2/bak" \
    "$1/scripts/sync.sh" "$4" --skip-npm --skip-herdr --skip-pi --firstmate-home "$2/fm" >"$S/out" 2>&1 || RC=$?
  OUT=$(cat "$S/out")
}

roles() { jq -r --arg t "$1" '.modelRoles[$t]' "$2/omp/config.yml"; }
dispatch() { jq -c "$1" "$2/fm/config/crew-dispatch.json"; }

# --- 1. Fresh machine, no local.json: the kit lands verbatim and a second check is clean.
K1="$S/k1"; M1="$S/m1"; new_kit "$K1"; new_machine "$M1"
run_sync "$K1" "$M1" "$M1/local.json" --apply
check "fresh apply exits 0" 0 "$RC"
check "fresh apply installs the kit's modelRoles" "$(jq -cS .modelRoles "$ROOT/omp/settings.json")" "$(jq -cS .modelRoles "$M1/omp/config.yml")"
check "fresh apply installs the kit's dispatch file" "$(jq -cS . "$ROOT/firstmate/crew-dispatch.json")" "$(jq -cS . "$M1/fm/config/crew-dispatch.json")"
run_sync "$K1" "$M1" "$M1/local.json" --check
check "fresh machine is in sync after apply" "In sync." "$(tail -n1 <<<"$OUT")"

# --- 2. Declared local additions survive, verbatim, after the kit's entries.
LOCAL="$S/local-additions.json"
cat >"$LOCAL" <<'JSON'
{
  "omp": {
    "modelRoles": {
      "cheap_local": "local/small-coder",
      "cheap": "@cheap_local",
      "mid": "@mid_local, @cheap_local",
      "mid_local": "local/mid-coder:high"
    }
  },
  "firstmate": {
    "use": {
      "cheap": [ { "harness": "omp", "model": "@cheap_local", "provider": "local" } ],
      "mid": [ { "harness": "omp", "model": "@mid_local", "provider": "local", "effort": "high" } ],
      "high": [ { "harness": "omp", "model": "@high_gemini", "provider": "agy", "effort": "auto" } ]
    },
    "rules": [
      { "when": "Docs-only edits", "use": [ { "harness": "omp", "model": "@cheap_gpt", "provider": "codex" } ], "select": "quota-balanced", "why": "Local docs rule" }
    ],
    "default": [
      { "harness": "omp", "model": "@mid_local", "provider": "local" },
      { "harness": "omp", "model": "@mid_gpt", "provider": "codex", "effort": "auto" }
    ]
  }
}
JSON
K2="$S/k2"; M2="$S/m2"; new_kit "$K2"; new_machine "$M2"
printf '{"modelRoles": {"cheap_claude": "local/stale"}}' >"$M2/omp/config.yml"
run_sync "$K2" "$M2" "$LOCAL" --apply
check "apply with local.json exits 0" 0 "$RC"
check "omp cheap = kit lanes then local lane" "@cheap_claude, @cheap_gpt, @cheap_gemini, @cheap_local" "$(roles cheap "$M2")"
check "omp mid = kit lanes then local lanes in declared order" "@mid_claude, @mid_gpt, @mid_gemini, @mid_agclaude, @mid_local, @cheap_local" "$(roles mid "$M2")"
check "omp high untouched by local.json" "@high_claude, @high_gpt, @high_gemini, @high_agclaude" "$(roles high "$M2")"
check "local role definitions are installed" '["local/small-coder","local/mid-coder:high"]' "$(jq -c '[.modelRoles.cheap_local, .modelRoles.mid_local]' "$M2/omp/config.yml")"
check "kit role definition wins over current config" "anthropic/claude-haiku-5-5:auto" "$(jq -r .modelRoles.cheap_claude "$M2/omp/config.yml")"
check "dispatch keeps the kit rules and appends the local rule" '["cheap","mid","high",null]' "$(dispatch '.rules | map(.tier)' "$M2")"
check "cheap rule = kit lanes with kit effort, then the local lane without effort" \
  '[["@cheap_gpt","auto"],["@cheap_claude","auto"],["@cheap_gemini","auto"],["@cheap_local",null]]' \
  "$(dispatch '.rules[0].use | map([.model, .effort])' "$M2")"
check "local lane effort is kept exactly" '[["@mid_local","high"]]' "$(dispatch '.rules[1].use[4:] | map([.model, .effort])' "$M2")"
check "local rule reusing a kit lane is kept whole" \
  '{"when":"Docs-only edits","use":[{"harness":"omp","model":"@cheap_gpt","provider":"codex"}],"select":"quota-balanced","why":"Local docs rule"}' \
  "$(dispatch '.rules[3]' "$M2")"
check "kit why text is installed on extended rules" "$(jq -r '.rules[0].why' "$ROOT/firstmate/crew-dispatch.json")" "$(jq -r '.rules[0].why' "$M2/fm/config/crew-dispatch.json")"
check "default = kit lanes then local lane" '["@mid_gpt","@mid_claude","@mid_gemini","@mid_agclaude","@mid_local"]' "$(dispatch '.default | map(.model)' "$M2")"
check "a local lane repeating a kit profile is written once in its rule" \
  '[["@high_gpt","auto"],["@high_claude","auto"],["@high_gemini","auto"],["@high_agclaude","auto"]]' \
  "$(dispatch '.rules[2].use | map([.model, .effort])' "$M2")"
check "no rule or default repeats a harness, model, effort profile" '[]' \
  "$(dispatch '[(.rules[].use), .default] | map(map([.harness, .model, .effort])) | map(select(length != (unique | length)))' "$M2")"
run_sync "$K2" "$M2" "$LOCAL" --check
check "machine with local.json is in sync after apply" "In sync." "$(tail -n1 <<<"$OUT")"
before=$(cat "$M2/omp/config.yml" "$M2/fm/config/crew-dispatch.json")
run_sync "$K2" "$M2" "$LOCAL" --apply
check "second apply changes nothing" "$before" "$(cat "$M2/omp/config.yml" "$M2/fm/config/crew-dispatch.json")"

# --- 3. The kit retires a lane and rewrites a rationale: both reach a synced machine, local additions stay.
jq '.modelRoles |= (del(.cheap_gemini) | .cheap = "@cheap_claude, @cheap_gpt")' "$K2/omp/settings.json" >"$K2/omp/settings.json.new"
mv "$K2/omp/settings.json.new" "$K2/omp/settings.json"
jq '.rules[0] |= (.use |= map(select(.model != "@cheap_gemini")) | .why = "Updated cheap rationale")' "$K2/firstmate/crew-dispatch.json" >"$K2/firstmate/crew-dispatch.json.new"
mv "$K2/firstmate/crew-dispatch.json.new" "$K2/firstmate/crew-dispatch.json"
run_sync "$K2" "$M2" "$LOCAL" --check
check "retired lane shows as drift" 1 "$RC"
run_sync "$K2" "$M2" "$LOCAL" --apply
check "retired omp lane leaves the tier list, local lane stays" "@cheap_claude, @cheap_gpt, @cheap_local" "$(roles cheap "$M2")"
check "retired dispatch lane leaves the rule, local lane stays" '["@cheap_gpt","@cheap_claude","@cheap_local"]' "$(dispatch '.rules[0].use | map(.model)' "$M2")"
check "kit rationale refresh reaches the extended rule" "Updated cheap rationale" "$(jq -r '.rules[0].why' "$M2/fm/config/crew-dispatch.json")"
check "local rule survives the kit change" "Docs-only edits" "$(jq -r '.rules[3].when' "$M2/fm/config/crew-dispatch.json")"
run_sync "$K2" "$M2" "$LOCAL" --check
check "in sync after the kit change" "In sync." "$(tail -n1 <<<"$OUT")"

# --- 4. No local.json and undeclared machine entries: report them and change nothing.
K4="$S/k4"; M4="$S/m4"; new_kit "$K4"; new_machine "$M4"
jq -c '.modelRoles | .cheap += ", @cheap_extra" | .cheap_extra = "local/extra"' "$ROOT/omp/settings.json" \
  | jq -c '{modelRoles: .}' >"$M4/omp/config.yml"
jq '.rules[0].use += [{"harness":"omp","model":"@cheap_extra","provider":"local"}]
    | .rules += [{"when":"Docs-only edits","use":[{"harness":"omp","model":"@cheap_gpt"}]}]
    | .default += [{"harness":"omp","model":"@mid_extra"}]' "$ROOT/firstmate/crew-dispatch.json" >"$M4/fm/config/crew-dispatch.json"
before=$(cat "$M4/omp/config.yml" "$M4/fm/config/crew-dispatch.json")
run_sync "$K4" "$M4" "$M4/local.json" --apply
check "apply refuses undeclared entries" 2 "$RC"
check "apply left omp and dispatch untouched" "$before" "$(cat "$M4/omp/config.yml" "$M4/fm/config/crew-dispatch.json")"
check "no backup directory was created by the refusal" "absent" "$([ -e "$M4/bak" ] && echo present || echo absent)"
check "refusal names the undeclared omp lane" 1 "$(grep -c 'MISSING omp modelRoles cheap: @cheap_extra' <<<"$OUT")"
check "refusal names the undeclared dispatch lane" 1 "$(grep -c 'MISSING firstmate rule cheap lanes: omp:@cheap_extra' <<<"$OUT")"
check "refusal names the undeclared dispatch rule" 1 "$(grep -c 'MISSING firstmate rule 4: Docs-only edits' <<<"$OUT")"
check "refusal names the undeclared default lane" 1 "$(grep -c 'MISSING firstmate default lanes: omp:@mid_extra' <<<"$OUT")"
check "refusal points at the local file" 1 "$(grep -c "declared in $M4/local.json" <<<"$OUT")"
run_sync "$K4" "$M4" "$M4/local.json" --check
CHECK_OUT=$OUT
check "check reports undeclared entries and exits 1" 1 "$RC"
check "check still lists them as MISSING" 1 "$(grep -c 'MISSING omp modelRoles cheap: @cheap_extra' <<<"$OUT")"

# --- 5. An empty local.json is the explicit choice to let the kit own the lists.
printf '{}\n' >"$M4/local.json"
run_sync "$K4" "$M4" "$M4/local.json" --apply
check "empty local.json lets apply proceed" 0 "$RC"
check "undeclared omp lane is dropped" "@cheap_claude, @cheap_gpt, @cheap_gemini" "$(roles cheap "$M4")"
check "undeclared dispatch additions are dropped" "$(jq -cS . "$ROOT/firstmate/crew-dispatch.json")" "$(jq -cS . "$M4/fm/config/crew-dispatch.json")"
check "the pre-change files were backed up" 2 "$(find "$M4/bak" -type f | wc -l | tr -d ' ')"
check "check guidance points at migration, not a plain apply" 1 "$(grep -c 'apply will stop until the machine-local entries above are declared' <<<"$CHECK_OUT")"

# --- 6. A malformed local.json is rejected before anything changes.
K6="$S/k6"; M6="$S/m6"; new_kit "$K6"; new_machine "$M6"
printf '{"firstmate": {"use": {"turbo": []}}}\n' >"$M6/local.json"
run_sync "$K6" "$M6" "$M6/local.json" --apply
check "unknown tier in local.json is rejected" 2 "$RC"
check "rejection names the allowed tiers" 1 "$(grep -c 'firstmate.use tiers must be among: cheap, mid, high' <<<"$OUT")"
check "rejection wrote no omp config" "absent" "$([ -e "$M6/omp/config.yml" ] && echo present || echo absent)"
printf '{"firstmate": {"preferred_provider": "codex"}}\n' >"$M6/local.json"
run_sync "$K6" "$M6" "$M6/local.json" --apply
check "unknown firstmate key in local.json is rejected" 2 "$RC"
check "rejection names the accepted firstmate keys" 1 "$(grep -c 'firstmate keys must be use, rules, or default' <<<"$OUT")"
check "rejection wrote no dispatch file" "absent" "$([ -e "$M6/fm/config/crew-dispatch.json" ] && echo present || echo absent)"
printf '{"omp": {"defaultThinkingLevel": "high"}}\n' >"$M6/local.json"
run_sync "$K6" "$M6" "$M6/local.json" --apply
check "scalar kit keys cannot be overridden locally" 2 "$RC"
check "rejection names the record-valued kit keys" 1 "$(grep -c 'omp keys must be record-valued kit keys' <<<"$OUT")"

printf '\n%d checks, %d failed\n' "$CASES" "$FAILS"
[ "$FAILS" = 0 ]
