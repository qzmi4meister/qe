#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${QE_SIGN_IDENTITY:?Set QE_SIGN_IDENTITY to a Developer ID Application identity}"
: "${QE_NOTARY_PROFILE:?Set QE_NOTARY_PROFILE to a notarytool Keychain profile}"
export QE_SIGN_IDENTITY
version=$(cat VERSION)
archive="QE-$version-arm64.zip"
mkdir -p .build dist
if [ -e "dist/$archive" ]; then
    printf 'Archive already exists: dist/%s. Update VERSION for a new release.\n' "$archive" >&2
    exit 1
fi
staging_dir=$(mktemp -d "$PWD/.build/release.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT HUP INT TERM
QE_APP_DIR="$staging_dir/QE.app" ./scripts/build.sh
codesign --verify --strict "$staging_dir/QE.app"
codesign --display --verbose=2 "$staging_dir/QE.app" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:'
ditto -c -k --sequesterRsrc --keepParent "$staging_dir/QE.app" "$staging_dir/submit.zip"
submission="$PWD/.build/notary-$version.json"
xcrun notarytool submit "$staging_dir/submit.zip" \
    --keychain-profile "$QE_NOTARY_PROFILE" --wait --output-format json > "$submission"
python3 - "$submission" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(Path(sys.argv[1]).read_text())
print(f"Notarization {result['id']}: {result['status']}")
if result['status'] != 'Accepted':
    sys.exit('Notarization failed. Retrieve the submission log with notarytool log.')
PY
xcrun stapler staple "$staging_dir/QE.app"
xcrun stapler validate "$staging_dir/QE.app"
codesign --verify --strict "$staging_dir/QE.app"
spctl --assess --type execute --verbose=2 "$staging_dir/QE.app"
ditto -c -k --sequesterRsrc --keepParent "$staging_dir/QE.app" "dist/$archive"
cd dist
shasum -a 256 "$archive" > SHA256SUMS
printf 'Built: dist/%s and dist/SHA256SUMS\n' "$archive"
