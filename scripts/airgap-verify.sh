#!/usr/bin/env bash
# airgap-verify.sh — Verify air gap enforcement blocks every cloud AI hostname
# Runs a local proxy, launches the app in debug mode with air gap on,
# triggers one call per provider, and confirms zero requests reach the proxy.
set -euo pipefail

PROXY_PORT=8888
RESULTS_FILE="scripts/airgap-results.json"
HOSTNAMES=(
  "api.anthropic.com"
  "api.openai.com"
  "generativelanguage.googleapis.com"
  "api.x.ai"
)

# Require mitmdump or equivalent for the proxy layer.
if ! command -v mitmdump >/dev/null 2>&1; then
  echo "ERROR: mitmdump not installed. Install via: brew install mitmproxy"
  exit 1
fi

echo "Starting mitmdump on :${PROXY_PORT}..."
mitmdump --listen-port "${PROXY_PORT}" --set confdir=./.mitmproxy \
  --flow-detail 0 --set save_stream_file="build/airgap-flows.txt" &
PROXY_PID=$!
sleep 2

cleanup() {
  kill "${PROXY_PID}" 2>/dev/null || true
}
trap cleanup EXIT

echo "Launching The Council with air_gap_enabled=true and HTTPS_PROXY set..."
HTTPS_PROXY="http://localhost:${PROXY_PORT}" \
  HTTP_PROXY="http://localhost:${PROXY_PORT}" \
  open -W -a build/TheCouncil.app --args --airgap-test || true

echo "Inspecting captured flows..."
PASS=true
RESULTS='{"hostnames":{}}'
for host in "${HOSTNAMES[@]}"; do
  COUNT=$(grep -c "${host}" build/airgap-flows.txt 2>/dev/null || echo "0")
  if [ "${COUNT}" -gt 0 ]; then
    echo "FAIL: ${host} — ${COUNT} requests reached proxy"
    PASS=false
  else
    echo "PASS: ${host}"
  fi
  RESULTS=$(echo "${RESULTS}" | jq --arg h "${host}" --arg c "${COUNT}" \
    '.hostnames[$h] = ($c | tonumber)')
done

echo "${RESULTS}" | jq --arg p "${PASS}" '. + {pass: ($p == "true")}' \
  > "${RESULTS_FILE}"

if [ "${PASS}" = "true" ]; then
  echo "Air gap verification PASSED"
  exit 0
else
  echo "Air gap verification FAILED — see ${RESULTS_FILE}"
  exit 1
fi
