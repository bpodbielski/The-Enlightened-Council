#!/usr/bin/env bash
# build-dmg.sh — Build a signed DMG of The Council
# Requires: Xcode command line tools, Developer ID certificate in Keychain
set -euo pipefail

PROJECT="TheCouncil.xcodeproj"
SCHEME="TheCouncil"
CONFIGURATION="Release"
BUILD_DIR="build"
DMG_NAME="TheCouncil"
VERSION=$(xcrun agvtool what-marketing-version -terse1 || echo "0.0.0")
DMG_PATH="${BUILD_DIR}/${DMG_NAME}-${VERSION}.dmg"

echo "Building ${SCHEME} (${CONFIGURATION}) v${VERSION}..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${BUILD_DIR}/${SCHEME}.xcarchive" \
  -quiet

xcodebuild -exportArchive \
  -archivePath "${BUILD_DIR}/${SCHEME}.xcarchive" \
  -exportPath "${BUILD_DIR}" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -quiet

APP_PATH="${BUILD_DIR}/${SCHEME}.app"

if [ ! -d "${APP_PATH}" ]; then
  echo "ERROR: ${APP_PATH} not found after export"
  exit 1
fi

echo "Creating DMG..."
hdiutil create \
  -volname "${DMG_NAME}" \
  -srcfolder "${APP_PATH}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "DMG created at ${DMG_PATH}"
echo "Run ./scripts/notarize.sh next"
