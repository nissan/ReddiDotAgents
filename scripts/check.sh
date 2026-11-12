#!/usr/bin/env bash
# ReddiDotAgents check: the one command to run, and paste the output of, before a change
# to this kit is merged. The repository has no hosted CI.
#
#   scripts/check.sh
#
# Part 1 needs only bash and jq and touches nothing outside this clone.
# Part 2 runs scripts/sync.sh against throwaway directories and needs omp. Without omp it
# is reported as NOT RUN and the script exits 3: a check that could not run is not a pass.
# Nothing here reads a real agent directory, a login, a session or an auth store.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
ok() { printf '  ok      %s\n' "$1"; }
bad() { printf '  FAIL    %s\n' "$1"; fail=1; }

echo "== static"
command -v jq >/dev/null || { echo "  FAIL    jq is not installed"; exit 1; }
jq --version 2>/dev/null | grep -q '^jq-' || bad "jq is not real jq (jaq breaks Firstmate's dispatch resolver)"
if bash -n scripts/sync.sh; then ok "scripts/sync.sh parses"; else bad "scripts/sync.sh does not parse"; fi
for f in omp/settings.json pi/settings.json firstmate/crew-dispatch.json firstmate/crew-dispatch.cursor.json; do
  if jq -e . "$f" >/dev/null 2>&1; then ok "$f is valid JSON"; else bad "$f is not valid JSON"; fi
done

# Every @role used by a tier or a dispatch candidate is a role the kit defines.
roles=$(jq -r '.modelRoles | keys[]' omp/settings.json)
used=$( { jq -r '.modelRoles[] | select(type == "string")' omp/settings.json | tr ', ' '\n\n' | grep '^@'
          jq -r '(.rules[].use[], .default[]) | .model' firstmate/crew-dispatch.json firstmate/crew-dispatch.cursor.json | grep '^@'; } | sort -u)
missing=0
for role in $used; do
  printf '%s\n' "$roles" | grep -qx "${role#@}" || { bad "role $role is used but not defined in omp/settings.json"; missing=1; }
done
[ "$missing" = 0 ] && ok "every @role in use is defined ($(printf '%s\n' "$used" | wc -l | tr -d ' ') roles)"

# A dispatch rule or default with no candidate makes Firstmate ignore every rule.
for f in firstmate/crew-dispatch.json firstmate/crew-dispatch.cursor.json; do
  if jq -e '(.default | length > 0) and ([.rules[].use | length > 0] | all)' "$f" >/dev/null; then
    ok "$f: every rule and the default have a candidate"
  else
    bad "$f: a rule or the default has no candidate"
  fi
done
[ "$fail" = 0 ] || { echo "Static checks failed."; exit 1; }

echo "== sync round trip (throwaway directories)"
if ! command -v omp >/dev/null; then
  echo "  NOT RUN omp is not installed, so scripts/sync.sh cannot run here."
  echo "Static checks passed. The sync round trip did NOT run: run this on a machine with omp before merging."
  exit 3
fi
S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/omp" "$S/pi"
mkdir -p "$S/firstmate/.git" "$S/firstmate/config"
printf 'existing owner retains this dispatch\n' >"$S/firstmate/config/crew-dispatch.json"
cp "$S/firstmate/config/crew-dispatch.json" "$S/legacy-before"
run() { FIRSTMATE_HOME="$S/firstmate" PI_CODING_AGENT_DIR="$S/omp" REDDIDOTAGENTS_PI_DIR="$S/pi" REDDIDOTAGENTS_BACKUP_DIR="$S/bak" \
  scripts/sync.sh "$@" --skip-npm --skip-herdr; }
if run --apply >"$S/apply.log" 2>&1; then ok "apply into empty directories"; else bad "apply failed"; tail -20 "$S/apply.log"; fi
if run --check >"$S/check.log" 2>&1 && grep -q 'In sync\.' "$S/check.log"; then
  ok "second check prints In sync."
else
  bad "second check did not print In sync."; tail -20 "$S/check.log"
fi
if cmp -s "$S/legacy-before" "$S/firstmate/config/crew-dispatch.json"; then
  ok "native default leaves existing Firstmate work untouched"
else
  bad "native default changed legacy Firstmate dispatch"
fi
if run --check --with-firstmate >"$S/legacy.log" 2>&1; then
  bad "explicit legacy check accepted unsupported Firstmate"
else
  status=$?
  if [ "$status" = 1 ]; then
    ok "explicit legacy check refuses unsupported Firstmate"
  else
    bad "legacy check failed unexpectedly (exit $status)"
  fi
fi
if run --apply --with-firstmate >"$S/legacy-apply.log" 2>&1; then
  bad "apply reported success with a missing legacy prerequisite"
else
  [ "$?" = 1 ] && ok "incomplete apply returns failure" || bad "unexpected incomplete-apply exit"
fi

# A practice-only refresh must not repair or overwrite unrelated runtime settings.
IFS= read -r begin <"$S/omp/AGENTS.md"
end=$(awk 'END { print }' "$S/omp/AGENTS.md")
PI_CODING_AGENT_DIR="$S/omp" omp config set defaultThinkingLevel high >/dev/null || bad "cannot seed user runtime setting"
printf '\n// User-owned canary extension change.\n' >>"$S/omp/extensions/provider-balancer.ts"
printf 'unparsed user-owned Pi settings\n' >"$S/pi/settings.json"
printf 'Personal prefix survives.\nPersonal suffix survives.\n' >"$S/omp/AGENTS.md"
cp "$S/omp/config.yml" "$S/config-before"
cp "$S/omp/extensions/provider-balancer.ts" "$S/extension-before"
cp "$S/pi/settings.json" "$S/pi-before"
if run --apply --rules-only >"$S/rules-apply.log" 2>&1 &&
   run --check --rules-only >"$S/rules-check.log" 2>&1 &&
   cmp -s "$S/config-before" "$S/omp/config.yml" &&
   cmp -s "$S/extension-before" "$S/omp/extensions/provider-balancer.ts" &&
   cmp -s "$S/pi-before" "$S/pi/settings.json" &&
   grep -qxF 'Personal prefix survives.' "$S/omp/AGENTS.md" &&
   grep -qxF 'Personal suffix survives.' "$S/omp/AGENTS.md"; then
  ok "rules-only refresh preserves settings, extensions and personal instructions"
else
  bad "rules-only refresh exceeded its scope"
fi
for malformed in missing-end duplicate reversed; do
  case "$malformed" in
  missing-end) printf 'Personal prefix\n%s\nold policy\nPersonal suffix\n' "$begin" ;;
  duplicate) printf '%s\n%s\n%s\n%s\nPersonal suffix\n' "$begin" "$end" "$begin" "$end" ;;
  reversed) printf '%s\nPersonal text\n%s\n' "$end" "$begin" ;;
  esac >"$S/omp/AGENTS.md"
  cp "$S/omp/AGENTS.md" "$S/instructions-before"
  if run --apply >"$S/malformed.log" 2>&1; then
    bad "$malformed block was accepted"
  elif cmp -s "$S/instructions-before" "$S/omp/AGENTS.md" &&
       cmp -s "$S/config-before" "$S/omp/config.yml" &&
       cmp -s "$S/extension-before" "$S/omp/extensions/provider-balancer.ts"; then
    ok "$malformed block is refused before runtime or instruction writes"
  else
    bad "$malformed refusal changed user files"
  fi
done
if run --apply --rules-only --with-firstmate >"$S/conflicting-scope.log" 2>&1; then
  bad "rules-only accepted a legacy write scope"
else
  [ "$?" = 2 ] && ok "conflicting write scopes are refused" || bad "unexpected scope-refusal exit"
fi
printf 'User-owned external instruction content.\n' >"$S/external-owner-file"
cp "$S/external-owner-file" "$S/external-before"
rm -f "$S/omp/AGENTS.md"
ln -s "$S/external-owner-file" "$S/omp/AGENTS.md"
if run --apply --rules-only >"$S/symlink.log" 2>&1; then
  bad "rules-only followed an instruction symlink"
elif [ -L "$S/omp/AGENTS.md" ] && cmp -s "$S/external-before" "$S/external-owner-file"; then
  ok "instruction symlinks are refused without following or replacing them"
else
  bad "symlink refusal changed user files"
fi
[ "$fail" = 0 ] || { echo "Sync round trip failed."; exit 1; }
echo "All checks passed."
