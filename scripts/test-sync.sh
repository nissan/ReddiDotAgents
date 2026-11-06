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

run_sync() { # <kit> <machine> <mode>: output in $OUT, exit status in $RC; local.json is read from <kit>
  RC=0
  PATH="$S/bin:$PATH" FAKE_OMP_DIR="$2/omp" REDDIDOTAGENTS_PI_DIR="$2/pi" \
    REDDIDOTAGENTS_BACKUP_DIR="$2/bak" \
    "$1/scripts/sync.sh" "$3" --skip-npm --skip-herdr --skip-pi --firstmate-home "$2/fm" >"$S/out" 2>&1 || RC=$?
  OUT=$(cat "$S/out")
}

roles() { jq -r --arg t "$1" '.modelRoles[$t]' "$2/omp/config.yml"; }
dispatch() { jq -c "$1" "$2/fm/config/crew-dispatch.json"; }

# --- 1. Fresh machine, no local.json: the kit lands verbatim and a second check is clean.
K1="$S/k1"; M1="$S/m1"; new_kit "$K1"; new_machine "$M1"
printf '%s\n' '{"accountPin":"personal","runtimePin":"pinned"}' >"$M1/omp/config.yml"
printf '%s\n' 'private configuration' >"$M1/fm/config/unmanaged"
run_sync "$K1" "$M1" --apply
check "fresh apply exits 0" 0 "$RC"
check "fresh apply installs the kit's modelRoles" "$(jq -cS .modelRoles "$ROOT/omp/settings.json")" "$(jq -cS .modelRoles "$M1/omp/config.yml")"
check "fresh apply installs the kit's dispatch file" "$(jq -cS . "$ROOT/firstmate/crew-dispatch.json")" "$(jq -cS . "$M1/fm/config/crew-dispatch.json")"
run_sync "$K1" "$M1" --check
check "fresh machine is in sync after apply" "In sync." "$(tail -n1 <<<"$OUT")"
cp "$K1/firstmate/crew-dispatch.json" "$S/original-dispatch-kit"

# A later kit revision may retire a kit-owned lane and change its explanation
# without making the unchanged previous installation look like a local edit.
mv "$M1/bak" "$M1/initial-bak"
M1WHY="$S/m1why"; new_machine "$M1WHY"
run_sync "$K1" "$M1WHY" --apply
jq '.rules[0].why = "Explanation only"' "$K1/firstmate/crew-dispatch.json" >"$S/dispatch-new"
mv "$S/dispatch-new" "$K1/firstmate/crew-dispatch.json"
run_sync "$K1" "$M1WHY" --check
check "explanation-only update previews as drift" 1 "$RC"
check "explanation-only update is not treated as local" 0 "$(grep -c 'MISSING' <<<"$OUT" || true)"
run_sync "$K1" "$M1WHY" --apply
check "explanation-only update applies" 0 "$RC"
check "explanation-only update reaches dispatch" "Explanation only" "$(jq -r '.rules[0].why' "$M1WHY/fm/config/crew-dispatch.json")"
cp "$S/original-dispatch-kit" "$K1/firstmate/crew-dispatch.json"
jq '.modelRoles |= (del(.cheap_gemini) | .cheap = "@cheap_claude, @cheap_gpt")' "$K1/omp/settings.json" >"$S/settings-new"
mv "$S/settings-new" "$K1/omp/settings.json"
jq '.rules[0] |= (.use |= map(select(.model != "@cheap_gemini")) | .why = "Updated rationale")' "$K1/firstmate/crew-dispatch.json" >"$S/dispatch-new"
mv "$S/dispatch-new" "$K1/firstmate/crew-dispatch.json"
cp "$M1/omp/config.yml" "$S/old-omp"
cp "$M1/fm/config/crew-dispatch.json" "$S/old-dispatch"
run_sync "$K1" "$M1" --check
check "historical kit changes preview as drift" 1 "$RC"
check "historical kit changes are not undeclared customizations" 0 "$(grep -c 'MISSING' <<<"$OUT" || true)"
check "preview leaves existing files untouched" "$(cat "$S/old-omp" "$S/old-dispatch")" "$(cat "$M1/omp/config.yml" "$M1/fm/config/crew-dispatch.json")"
jq '.modelRoles.cheap += ", @private"' "$S/old-omp" >"$M1/omp/config.yml"
run_sync "$K1" "$M1" --apply
check "custom tier addition still blocks historical refresh" 2 "$RC"
check "custom tier addition survives refusal" "@cheap_claude, @cheap_gpt, @cheap_gemini, @private" "$(roles cheap "$M1")"
cp "$S/old-omp" "$M1/omp/config.yml"
jq '.rules[0].floor = {"scope":"week","min_percent":20,"provider":"codex"}' "$S/old-dispatch" >"$M1/fm/config/crew-dispatch.json"
run_sync "$K1" "$M1" --apply
check "custom dispatch option still blocks historical refresh" 2 "$RC"
check "custom dispatch option survives refusal" 20 "$(dispatch '.rules[0].floor.min_percent' "$M1")"
cp "$S/old-dispatch" "$M1/fm/config/crew-dispatch.json"
run_sync "$K1" "$M1" --apply
check "historical refresh applies" 0 "$RC"
check "historical kit lane retires" "@cheap_claude, @cheap_gpt" "$(roles cheap "$M1")"
check "historical kit explanation updates" "Updated rationale" "$(jq -r '.rules[0].why' "$M1/fm/config/crew-dispatch.json")"
check "refresh preserves unrelated account and runtime settings" '["personal","pinned"]' "$(jq -c '[.accountPin,.runtimePin]' "$M1/omp/config.yml")"
check "refresh preserves unmanaged Firstmate file" 'private configuration' "$(cat "$M1/fm/config/unmanaged")"
check "refresh backs up previous omp settings" "$(cat "$S/old-omp")" "$(cat "$M1/bak"/*/"${M1#/}"/omp/config.yml)"
check "refresh backs up previous dispatch" "$(cat "$S/old-dispatch")" "$(cat "$M1/bak"/*/"${M1#/}"/fm/config/crew-dispatch.json)"
run_sync "$K1" "$M1" --check
check "historical refresh is in sync" "In sync." "$(tail -n1 <<<"$OUT")"
before=$(cat "$M1/omp/config.yml" "$M1/fm/config/crew-dispatch.json")
run_sync "$K1" "$M1" --apply
check "historical refresh is idempotent" "$before" "$(cat "$M1/omp/config.yml" "$M1/fm/config/crew-dispatch.json")"
jq '.rules[0].why = "Second update"' "$K1/firstmate/crew-dispatch.json" >"$S/dispatch-new"
mv "$S/dispatch-new" "$K1/firstmate/crew-dispatch.json"
run_sync "$K1" "$M1" --apply
check "second plain-copy refresh applies" 0 "$RC"
check "second plain-copy refresh uses updated baseline" "Second update" "$(jq -r '.rules[0].why' "$M1/fm/config/crew-dispatch.json")"

# Existing installations from before baseline bookkeeping may still use the
# unchanged values in the kit's committed history.
KH="$S/kh"; MH="$S/mh"; new_kit "$KH"; new_machine "$MH"
git -C "$KH" init -q
git -C "$KH" add omp/settings.json firstmate/crew-dispatch.json
git -C "$KH" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false commit -qm baseline
run_sync "$KH" "$MH" --apply
rm "$MH/omp/.reddidotagents-model-roles.json" "$MH/fm/config/.reddidotagents-crew-dispatch.json"
jq '.modelRoles.cheap = "@cheap_claude, @cheap_gpt"' "$KH/omp/settings.json" >"$S/settings-new"
mv "$S/settings-new" "$KH/omp/settings.json"
jq '.rules[0].why = "Historical upgrade"' "$KH/firstmate/crew-dispatch.json" >"$S/dispatch-new"
mv "$S/dispatch-new" "$KH/firstmate/crew-dispatch.json"
run_sync "$KH" "$MH" --apply
check "pre-bookkeeping install refreshes from committed kit history" 0 "$RC"
check "pre-bookkeeping retirement is applied" "@cheap_claude, @cheap_gpt" "$(roles cheap "$MH")"
check "pre-bookkeeping explanation is applied" "Historical upgrade" "$(jq -r '.rules[0].why' "$MH/fm/config/crew-dispatch.json")"

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
cp "$LOCAL" "$K2/local.json"
printf '{"modelRoles": {"cheap_claude": "local/stale"}}' >"$M2/omp/config.yml"
run_sync "$K2" "$M2" --apply
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
run_sync "$K2" "$M2" --check
check "machine with local.json is in sync after apply" "In sync." "$(tail -n1 <<<"$OUT")"
before=$(cat "$M2/omp/config.yml" "$M2/fm/config/crew-dispatch.json")
run_sync "$K2" "$M2" --apply
check "second apply changes nothing" "$before" "$(cat "$M2/omp/config.yml" "$M2/fm/config/crew-dispatch.json")"

# --- 3. The kit retires a lane and rewrites a rationale: both reach a synced machine, local additions stay.
jq '.modelRoles |= (del(.cheap_gemini) | .cheap = "@cheap_claude, @cheap_gpt")' "$K2/omp/settings.json" >"$K2/omp/settings.json.new"
mv "$K2/omp/settings.json.new" "$K2/omp/settings.json"
jq '.rules[0] |= (.use |= map(select(.model != "@cheap_gemini")) | .why = "Updated cheap rationale")' "$K2/firstmate/crew-dispatch.json" >"$K2/firstmate/crew-dispatch.json.new"
mv "$K2/firstmate/crew-dispatch.json.new" "$K2/firstmate/crew-dispatch.json"
run_sync "$K2" "$M2" --check
check "retired lane shows as drift" 1 "$RC"
run_sync "$K2" "$M2" --apply
check "retired omp lane leaves the tier list, local lane stays" "@cheap_claude, @cheap_gpt, @cheap_local" "$(roles cheap "$M2")"
check "retired dispatch lane leaves the rule, local lane stays" '["@cheap_gpt","@cheap_claude","@cheap_local"]' "$(dispatch '.rules[0].use | map(.model)' "$M2")"
check "kit rationale refresh reaches the extended rule" "Updated cheap rationale" "$(jq -r '.rules[0].why' "$M2/fm/config/crew-dispatch.json")"
check "local rule survives the kit change" "Docs-only edits" "$(jq -r '.rules[3].when' "$M2/fm/config/crew-dispatch.json")"
run_sync "$K2" "$M2" --check
check "in sync after the kit change" "In sync." "$(tail -n1 <<<"$OUT")"
mv "$K2/local.json" "$S/removed-local.json"
before=$(cat "$M2/omp/config.yml" "$M2/fm/config/crew-dispatch.json")
run_sync "$K2" "$M2" --apply
check "removing local.json does not authorize dropping its additions" 2 "$RC"
check "removed local.json leaves installed additions intact" "$before" "$(cat "$M2/omp/config.yml" "$M2/fm/config/crew-dispatch.json")"
mv "$S/removed-local.json" "$K2/local.json"

# --- 4. No local.json and undeclared machine entries: report them and change nothing.
K4="$S/k4"; M4="$S/m4"; new_kit "$K4"; new_machine "$M4"
jq -c '.modelRoles | .cheap += ", @cheap_extra" | .cheap_extra = "local/extra"' "$ROOT/omp/settings.json" \
  | jq -c '{modelRoles: .}' >"$M4/omp/config.yml"
jq '.rules[0].use += [{"harness":"omp","model":"@cheap_extra","provider":"local"}]
    | .rules += [{"when":"Docs-only edits","use":[{"harness":"omp","model":"@cheap_gpt"}]}]
    | .default += [{"harness":"omp","model":"@mid_extra"}]' "$ROOT/firstmate/crew-dispatch.json" >"$M4/fm/config/crew-dispatch.json"
before=$(cat "$M4/omp/config.yml" "$M4/fm/config/crew-dispatch.json")
run_sync "$K4" "$M4" --apply
check "apply refuses undeclared entries" 2 "$RC"
check "apply left omp and dispatch untouched" "$before" "$(cat "$M4/omp/config.yml" "$M4/fm/config/crew-dispatch.json")"
check "no backup directory was created by the refusal" "absent" "$([ -e "$M4/bak" ] && echo present || echo absent)"
check "refusal names the undeclared omp lane" 1 "$(grep -c 'MISSING omp modelRoles cheap: @cheap_extra' <<<"$OUT")"
check "refusal reports the dispatch file as differing from the kit" 1 "$(grep -c 'MISSING firstmate config/crew-dispatch.json differs from the kit baseline' <<<"$OUT")"
check "refusal points at the local file" 1 "$(grep -c "declared in $K4/local.json" <<<"$OUT")"
run_sync "$K4" "$M4" --check
CHECK_OUT=$OUT
check "check reports undeclared entries and exits 1" 1 "$RC"
check "check still lists them as MISSING" 1 "$(grep -c 'MISSING omp modelRoles cheap: @cheap_extra' <<<"$OUT")"

# --- 4b. Any difference from the kit's dispatch file stops the run (reordered rules, object-form lanes, effort
#         variants, extra top-level keys, rule-level options); declaring the entries, or an empty local.json, lets it proceed.
K4b="$S/k4b"; M4b="$S/m4b"; new_kit "$K4b"; new_machine "$M4b"
jq '{rules: ([{"when":"Docs-only edits","use":[{"harness":"omp","model":"@cheap_gpt"}]}] + (.rules | map(del(.tier)))), default}' \
  "$ROOT/firstmate/crew-dispatch.json" >"$M4b/fm/config/crew-dispatch.json"
run_sync "$K4b" "$M4b" --check
check "reordered file still stops the run" 1 "$RC"
check "a reordered dispatch file is reported once" 1 "$(grep -c 'MISSING firstmate' <<<"$OUT")"
jq '.default = {"harness": "omp", "model": "@mine", "provider": "codex"}' "$ROOT/firstmate/crew-dispatch.json" >"$M4b/fm/config/crew-dispatch.json"
run_sync "$K4b" "$M4b" --apply
check "an object-form default lane the kit does not define stops the run" 2 "$RC"
jq '.rules[0].use = {"harness": "omp", "model": "@solo", "provider": "codex"}' "$ROOT/firstmate/crew-dispatch.json" >"$M4b/fm/config/crew-dispatch.json"
run_sync "$K4b" "$M4b" --apply
check "an object-form rule lane the kit does not define stops the run" 2 "$RC"
jq '.rules[0].use += [{"harness": "omp", "model": "@cheap_gpt", "provider": "codex", "effort": "high"}]
    | .default += [{"harness": "omp", "model": "@mid_gpt", "provider": "codex", "effort": "high"}]' \
  "$ROOT/firstmate/crew-dispatch.json" >"$M4b/fm/config/crew-dispatch.json"
before=$(cat "$M4b/fm/config/crew-dispatch.json")
run_sync "$K4b" "$M4b" --apply
check "a kit model at a different effort is a distinct lane and stops the run" 2 "$RC"
check "the effort variant was not dropped" "$before" "$(cat "$M4b/fm/config/crew-dispatch.json")"
cat >"$K4b/local.json" <<'JSON'
{ "firstmate": { "use": { "cheap": [ { "harness": "omp", "model": "@cheap_gpt", "provider": "codex", "effort": "high" } ] },
                 "default": [ { "harness": "omp", "model": "@mid_gpt", "provider": "codex", "effort": "high" } ] } }
JSON
run_sync "$K4b" "$M4b" --apply
check "declared effort variant lets apply proceed" 0 "$RC"
check "declared effort variant is kept beside the kit's auto lane" '[["@cheap_gpt","auto"],["@cheap_gpt","high"]]' \
  "$(dispatch '.rules[0].use | map(select(.model == "@cheap_gpt") | [.model, .effort])' "$M4b")"
check "declared default effort variant is kept beside the kit's auto lane" '[["@mid_gpt","auto"],["@mid_gpt","high"]]' \
  "$(dispatch '.default | map(select(.model == "@mid_gpt") | [.model, .effort])' "$M4b")"
run_sync "$K4b" "$M4b" --check
check "machine with a declared effort variant is in sync" "In sync." "$(tail -n1 <<<"$OUT")"
rm "$K4b/local.json"
jq '.preferred_provider = "codex"' "$ROOT/firstmate/crew-dispatch.json" >"$M4b/fm/config/crew-dispatch.json"
run_sync "$K4b" "$M4b" --check
check "a top-level key the kit does not write stops the check" 1 "$RC"
jq '.rules[0].floor = {"scope": "week", "min_percent": 20, "provider": "codex"} | .rules[1].approval = "captain"' \
  "$ROOT/firstmate/crew-dispatch.json" >"$M4b/fm/config/crew-dispatch.json"
before=$(cat "$M4b/fm/config/crew-dispatch.json")
run_sync "$K4b" "$M4b" --apply
check "rule-level options the kit does not set stop the run" 2 "$RC"
check "the rule-level options were not dropped" "$before" "$(cat "$M4b/fm/config/crew-dispatch.json")"
printf '{}\n' >"$K4b/local.json"
run_sync "$K4b" "$M4b" --apply
check "an empty local.json accepts the kit baseline" 0 "$RC"
check "the kit baseline replaced the rule-level options" "$(jq -cS . "$ROOT/firstmate/crew-dispatch.json")" "$(jq -cS . "$M4b/fm/config/crew-dispatch.json")"
rm "$K4b/local.json"

# --- 5. An empty local.json is the explicit choice to let the kit own the lists.
printf '{}\n' >"$K4/local.json"
run_sync "$K4" "$M4" --apply
check "empty local.json lets apply proceed" 0 "$RC"
check "undeclared omp lane is dropped" "@cheap_claude, @cheap_gpt, @cheap_gemini" "$(roles cheap "$M4")"
check "undeclared dispatch additions are dropped" "$(jq -cS . "$ROOT/firstmate/crew-dispatch.json")" "$(jq -cS . "$M4/fm/config/crew-dispatch.json")"
check "the pre-change files were backed up" 2 "$(find "$M4/bak" -type f | wc -l | tr -d ' ')"
check "check guidance points at migration, not a plain apply" 1 "$(grep -c 'apply will stop until the machine-local entries above are declared' <<<"$CHECK_OUT")"

# --- 6. A malformed local.json is rejected before anything changes.
K6="$S/k6"; M6="$S/m6"; new_kit "$K6"; new_machine "$M6"
printf '{"firstmate": {"use": {"turbo": []}}}\n' >"$K6/local.json"
run_sync "$K6" "$M6" --apply
check "unknown tier in local.json is rejected" 2 "$RC"
check "rejection names the allowed tiers" 1 "$(grep -c 'firstmate.use tiers must be among: cheap, mid, high' <<<"$OUT")"
check "rejection wrote no omp config" "absent" "$([ -e "$M6/omp/config.yml" ] && echo present || echo absent)"
printf '{"firstmate": {"preferred_provider": "codex"}}\n' >"$K6/local.json"
run_sync "$K6" "$M6" --apply
check "unknown firstmate key in local.json is rejected" 2 "$RC"
check "rejection names the accepted firstmate keys" 1 "$(grep -c 'firstmate keys must be use, rules, or default' <<<"$OUT")"
check "rejection wrote no dispatch file" "absent" "$([ -e "$M6/fm/config/crew-dispatch.json" ] && echo present || echo absent)"
printf '{"firstmate": {"rules": [{"use": [{"harness": "omp", "model": "@cheap_gpt"}]}]}}\n' >"$K6/local.json"
run_sync "$K6" "$M6" --apply
check "a local rule without when is rejected" 2 "$RC"
check "rejection names the rule shape" 1 "$(grep -c 'each firstmate.rules entry must be an object with a non-empty when' <<<"$OUT")"
printf '{"firstmate": {"use": {"cheap": [{"model": "@cheap_local"}]}}}\n' >"$K6/local.json"
run_sync "$K6" "$M6" --apply
check "a local lane without harness is rejected" 2 "$RC"
check "rejection names the lane shape" 1 "$(grep -c 'each firstmate.use.<tier> profile must be an object with a non-empty harness' <<<"$OUT")"
printf '{"firstmate": {"default": ["@mid_local"]}}\n' >"$K6/local.json"
run_sync "$K6" "$M6" --apply
check "a default entry that is not a profile object is rejected" 2 "$RC"
check "rejection wrote no dispatch file after shape errors" "absent" "$([ -e "$M6/fm/config/crew-dispatch.json" ] && echo present || echo absent)"
printf '{"omp": {"defaultThinkingLevel": "high"}}\n' >"$K6/local.json"
run_sync "$K6" "$M6" --apply
check "omp keys other than modelRoles are rejected" 2 "$RC"
printf '{"omp": {"modelRoles": {"cheap": ["@cheap_local"], "cheap_local": "local/small-coder"}}}\n' >"$K6/local.json"
run_sync "$K6" "$M6" --apply
check "a non-string tier value is rejected instead of ignored" 2 "$RC"
check "rejection wrote no omp config for the bad tier value" "absent" "$([ -e "$M6/omp/config.yml" ] && echo present || echo absent)"
for bad in \
  '{"firstmate": {"use": {"cheap": [{"harness": "omp", "model": "@cheap_local"}]}}}' \
  '{"firstmate": {"default": [{"harness": "omp", "model": "@mid_local", "provider": "local", "effort": "ultra"}]}}' \
  '{"firstmate": {"use": {"mid": [{"harness": "omp", "model": "", "provider": "local"}]}}}' \
  '{"firstmate": {"use": {"mid": [{"harness": "omp", "model": "@mid_local", "provider": "Local"}]}}}' \
  '{"firstmate": {"default": [{"harness": "claude", "model": "opus", "provider": "my_provider"}]}}' \
  '{"firstmate": {"rules": [{"when": "Docs", "use": [{"harness": "omp", "model": "@cheap_gpt", "provider": "codex"}], "select": "first"}]}}' \
  '{"firstmate": {"rules": [{"when": "Docs", "use": [{"harness": "omp", "model": "@cheap_gpt", "provider": "codex"}, {"harness": "omp", "model": "@cheap_gpt", "provider": "codex"}]}]}}'; do
  printf '%s\n' "$bad" >"$K6/local.json"
  run_sync "$K6" "$M6" --apply
  check "Firstmate would reject it, so the sync does: $bad" 2 "$RC"
done
check "no dispatch file was written by any rejected overlay" "absent" "$([ -e "$M6/fm/config/crew-dispatch.json" ] && echo present || echo absent)"

printf '\n%d checks, %d failed\n' "$CASES" "$FAILS"
[ "$FAILS" = 0 ]
