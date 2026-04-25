#!/usr/bin/env bash
# notarize.sh — Submit the DMG to Apple notary service and staple the ticket
# Requires: xcrun notarytool credentials configured under profile "the-council"
set -euo pipefail

DMG_PATH="${1:-}"
if [ -z "${DMG_PATH}" ]; then
  DMG_PATH=$(ls -t build/TheCouncil-*.dmg 2>/dev/null | head -n 1 || echo "")
fi

if [ -z "${DMG_PATH}" ] || [ ! -f "${DMG_PATH}" ]; then
  echo "ERROR: no DMG path given and none found in build/"
  echo "Usage: ./scripts/notarize.sh [path/to/file.dmg]"
  exit 1
fi

echo "Submitting ${DMG_PATH} for notarization..."
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "the-council" \
  --wait

echo "Stapling ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "Validating stapled DMG..."
xcrun stapler validate "${DMG_PATH}"

echo "Notarization complete: ${DMG_PATH}"
