#!/bin/bash
# Build and install CobraKey to /Applications with proper code signing.
# Usage: ./install.sh
#
# Set DEVELOPMENT_TEAM to your Apple Developer Team ID for stable signing.
# Without it, the app uses ad-hoc signing (permissions may reset on rebuild).

set -euo pipefail

TEAM="${DEVELOPMENT_TEAM:-}"
EXTRA_ARGS=()
if [ -n "$TEAM" ]; then
    EXTRA_ARGS+=("DEVELOPMENT_TEAM=$TEAM")
    echo "Signing with team: $TEAM"
else
    echo "Warning: No DEVELOPMENT_TEAM set. Using ad-hoc signing."
    echo "  Export DEVELOPMENT_TEAM=<your-team-id> for stable Accessibility permissions."
fi

echo "Building CobraKey (Release)..."
xcodebuild -project CobraKey.xcodeproj \
    -scheme CobraKey \
    -configuration Release \
    -derivedDataPath build \
    "${EXTRA_ARGS[@]}" \
    -quiet

echo "Installing to /Applications..."
pkill -x CobraKey 2>/dev/null || true
sleep 1
rm -rf /Applications/CobraKey.app
cp -R build/Build/Products/Release/CobraKey.app /Applications/
xattr -cr /Applications/CobraKey.app

echo "Launching CobraKey..."
open /Applications/CobraKey.app
echo "Done. Grant Accessibility permission if prompted, then enable 'Start at Login'."
