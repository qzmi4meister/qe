#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
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
ditto -c -k --sequesterRsrc --keepParent "$staging_dir/QE.app" "dist/$archive"
cd dist
shasum -a 256 "$archive" > SHA256SUMS
printf 'Built: dist/%s and dist/SHA256SUMS\n' "$archive"
