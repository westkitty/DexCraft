#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/DexCraft.xcodeproj"
SCHEME="DexCraft"
DERIVED_DATA_PATH="$ROOT_DIR/build-install"
APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/Release/DexCraft.app"
APP_DESTINATION="/Applications/DexCraft.app"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Project not found at $PROJECT_PATH" >&2
  exit 1
fi

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Built app not found at $APP_SOURCE" >&2
  exit 1
fi

# Install to /Applications so the app appears in the Applications folder and can be launched from there.
ditto "$APP_SOURCE" "$APP_DESTINATION"

echo "Installed DexCraft to: $APP_DESTINATION"
