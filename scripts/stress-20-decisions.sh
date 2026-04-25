#!/usr/bin/env bash
# stress-20-decisions.sh — Drive 20 decisions end-to-end for the Phase 10 ship gate
# Designed to be run against a debug build with a seed decision fixture set.
set -euo pipefail

FIXTURE_DIR="scripts/stress-fixtures"
RESULTS_FILE="scripts/stress-results.json"
APP_PATH="build/TheCouncil.app"

if [ ! -d "${APP_PATH}" ]; then
  echo "ERROR: ${APP_PATH} not found. Run ./scripts/build-dmg.sh first (or build Debug)."
  exit 1
fi

if [ ! -d "${FIXTURE_DIR}" ]; then
  echo "ERROR: ${FIXTURE_DIR} not found. Create 20 seed decision briefs as .json files."
  exit 1
fi

FIXTURES=("${FIXTURE_DIR}"/*.json)
TOTAL=${#FIXTURES[@]}
if [ "${TOTAL}" -lt 20 ]; then
  echo "ERROR: need at least 20 fixtures in ${FIXTURE_DIR}, found ${TOTAL}"
  exit 1
fi

echo "Running stress test across ${TOTAL} fixtures..."
PASS=0
FAIL=0
CRASHES=0

for fixture in "${FIXTURES[@]}"; do
  echo "--- Running ${fixture} ---"
  if open -W -a "${APP_PATH}" --args --stress-run "${fixture}"; then
    PASS=$((PASS+1))
  else
    EXIT_CODE=$?
    FAIL=$((FAIL+1))
    if [ "${EXIT_CODE}" -ge 128 ]; then
      CRASHES=$((CRASHES+1))
    fi
  fi
done

jq -n \
  --argjson total "${TOTAL}" \
  --argjson pass "${PASS}" \
  --argjson fail "${FAIL}" \
  --argjson crashes "${CRASHES}" \
  '{total: $total, pass: $pass, fail: $fail, crashes: $crashes}' \
  > "${RESULTS_FILE}"

echo "Stress results: ${PASS}/${TOTAL} passed, ${FAIL} failed, ${CRASHES} crashes"
echo "Written to ${RESULTS_FILE}"

if [ "${CRASHES}" -gt 0 ]; then
  echo "FAIL: ${CRASHES} crashes is above the SPEC §13 gate of zero"
  exit 1
fi

echo "PASS: zero crashes"
