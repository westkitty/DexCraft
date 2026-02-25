#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/DexCraft.xcodeproj"
SCHEME="DexCraft"
DERIVED_DATA_PATH="$ROOT_DIR/build-install"
APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/Release/DexCraft.app"
APP_DESTINATION="/Applications/DexCraft.app"
EMBEDDED_RUNTIME_SOURCE="$ROOT_DIR/Tools/embedded-tiny-runtime/macos-arm64"
EMBEDDED_RUNTIME_DESTINATION="$APP_DESTINATION/Contents/Resources/EmbeddedTinyRuntime"

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

if [[ -d "$EMBEDDED_RUNTIME_SOURCE" ]]; then
  mkdir -p "$EMBEDDED_RUNTIME_DESTINATION"
  ditto "$EMBEDDED_RUNTIME_SOURCE" "$EMBEDDED_RUNTIME_DESTINATION"
  chmod +x "$EMBEDDED_RUNTIME_DESTINATION/llama-completion" || true
  if command -v codesign >/dev/null 2>&1; then
    find "$EMBEDDED_RUNTIME_DESTINATION" -type f \( -name "*.dylib" -o -name "llama-completion" \) -print0 | while IFS= read -r -d '' file; do
      codesign --force --sign - "$file" >/dev/null 2>&1 || true
    done
  fi
else
  echo "Warning: Embedded tiny runtime source not found at $EMBEDDED_RUNTIME_SOURCE" >&2
fi

echo "Installed DexCraft to: $APP_DESTINATION"
