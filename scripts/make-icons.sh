#!/usr/bin/env bash
# Rasterizes design/icon/*.svg into the app icon and the README image.
# Headless Chrome is the renderer (no rsvg/imagemagick on this machine);
# a small Swift pass strips the alpha channel, which the App Store requires.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Google Chrome not found — cannot rasterize"; exit 1; }

ICONSET="App/Resources/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

render() { # svg size out
  local svg="$1" size="$2" out="$3"
  cat > "$TMP/page.html" <<HTML
<html><body style="margin:0"><img src="file://$PWD/$svg" width="$size" height="$size"></body></html>
HTML
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --default-background-color=00000000 \
    --window-size="$size,$size" --screenshot="$out" "file://$TMP/page.html" 2>/dev/null
}

render docs/assets/icon/listnr-icon.svg 1024 "$TMP/appicon.png"
render docs/assets/icon/listnr-icon-rounded.svg 512 "docs/assets/listnr-icon-512.png"

# App icons must ship without an alpha channel.
cat > "$TMP/flatten.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let src = URL(fileURLWithPath: CommandLine.arguments[1])
let dst = URL(fileURLWithPath: CommandLine.arguments[2])
guard let provider = CGDataProvider(url: src as CFURL),
      let image = CGImage(pngDataProviderSource: provider, decode: nil,
                          shouldInterpolate: true, intent: .defaultIntent),
      let ctx = CGContext(data: nil, width: image.width, height: image.height,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    FileHandle.standardError.write(Data("cannot read \(src.path)\n".utf8))
    exit(1)
}
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard let flat = ctx.makeImage(),
      let out = CGImageDestinationCreateWithURL(dst as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(out, flat, nil)
CGImageDestinationFinalize(out)
SWIFT
mkdir -p "$ICONSET"
xcrun swift "$TMP/flatten.swift" "$TMP/appicon.png" "$ICONSET/AppIcon-1024.png"

echo "wrote $ICONSET/AppIcon-1024.png and docs/assets/listnr-icon-512.png"
