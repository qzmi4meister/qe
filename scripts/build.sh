#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=$(cat VERSION)
if ! printf '%s\n' "$version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf 'VERSION must contain a version such as 0.3.0.\n' >&2
    exit 1
fi
swift build -c release --arch arm64 --product QE
app_dir="${QE_APP_DIR:-$PWD/dist/QE.app}"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/arm64-apple-macosx/release/QE "$app_dir/Contents/MacOS/QE"
/usr/bin/strip -S "$app_dir/Contents/MacOS/QE"
cp LICENSE "$app_dir/Contents/Resources/LICENSE"
iconset_dir="$PWD/.build/QE.iconset"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon-fullbleed.png --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" Resources/AppIcon-fullbleed.png --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_dir" -o "$app_dir/Contents/Resources/AppIcon.icns"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QE</string>
<key>CFBundleIdentifier</key><string>local.qe.files</string>
<key>CFBundleName</key><string>QE</string>
<key>CFBundleDisplayName</key><string>QE</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string></array>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 qzmi4meister. MIT License.</string>
</dict></plist>
PLIST
if [ -n "${QE_SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$QE_SIGN_IDENTITY" "$app_dir"
else
    codesign --force --sign - "$app_dir"
fi
printf 'Built: %s\n' "$app_dir"
