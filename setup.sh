#!/usr/bin/env bash
set -euo pipefail

SOURCE_IMAGE="/Users/andrew/Library/CloudStorage/GoogleDrive-digitalghosts269@gmail.com/My Drive/macbook/DexCraft_Icon.png"
ASSET_ROOT="DexCraft/Resources/Assets.xcassets"
IMAGESET_DIR="$ASSET_ROOT/DexCraftWatermark.imageset"

if [[ ! -f "$SOURCE_IMAGE" ]]; then
  echo "Source image not found: $SOURCE_IMAGE" >&2
  exit 1
fi

mkdir -p "$IMAGESET_DIR"

if ! cp "$SOURCE_IMAGE" "$IMAGESET_DIR/DexCraftWatermark.png"; then
  echo "Failed to copy source image from Google Drive path." >&2
  echo "Grant your terminal app Files & Folders access for Google Drive, then rerun setup.sh." >&2
  exit 1
fi

cat > "$IMAGESET_DIR/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "DexCraftWatermark.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

if [[ ! -f "$ASSET_ROOT/Contents.json" ]]; then
  cat > "$ASSET_ROOT/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
fi

echo "Installed DexCraftWatermark asset at: $IMAGESET_DIR"
