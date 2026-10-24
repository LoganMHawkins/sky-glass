#!/bin/bash
# Archives Skyglass and uploads it to App Store Connect for TestFlight.
# Needs: an app record for ca.theboldbureau.skyglass in App Store Connect,
# and Xcode signed in to your Apple ID (Xcode > Settings > Accounts).
# Usage: Tools/testflight.sh [build-number]   (defaults to a timestamp; every upload needs a new one)
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${1:-$(date +%y%m%d%H%M)}"
OUT="$(mktemp -d)"
xcodegen generate >/dev/null
echo "Archiving build $BUILD..."
xcodebuild archive -project Skyglass.xcodeproj -scheme Skyglass -destination "generic/platform=iOS" \
  -archivePath "$OUT/Skyglass.xcarchive" -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" | tail -3
echo "Uploading to App Store Connect..."
xcodebuild -exportArchive -archivePath "$OUT/Skyglass.xcarchive" -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates | tail -5
echo "Done. The build appears in App Store Connect > TestFlight after processing (usually 5-20 minutes)."
