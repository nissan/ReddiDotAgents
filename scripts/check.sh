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
run() { PI_CODING_AGENT_DIR="$S/omp" REDDIDOTAGENTS_PI_DIR="$S/pi" REDDIDOTAGENTS_BACKUP_DIR="$S/bak" \
  scripts/sync.sh "$@" --skip-npm --skip-herdr --firstmate-home "$S/none"; }
if run --apply >"$S/apply.log" 2>&1; then ok "apply into empty directories"; else bad "apply failed"; tail -20 "$S/apply.log"; fi
if run --check >"$S/check.log" 2>&1 && grep -q 'In sync\.' "$S/check.log"; then
  ok "second check prints In sync."
else
  bad "second check did not print In sync."; tail -20 "$S/check.log"
fi
[ "$fail" = 0 ] || { echo "Sync round trip failed."; exit 1; }
echo "All checks passed."
