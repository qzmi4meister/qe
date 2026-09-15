#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=$(cat VERSION)
archive="QE-$version-arm64.zip"
mkdir -p .build dist
if [ -e "dist/$archive" ]; then
    printf 'Архив уже существует: dist/%s. Для нового релиза измените VERSION.\n' "$archive" >&2
    exit 1
fi
staging_dir=$(mktemp -d "$PWD/.build/release.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT HUP INT TERM
QE_APP_DIR="$staging_dir/QE.app" ./scripts/build.sh
codesign --verify --strict "$staging_dir/QE.app"
ditto -c -k --sequesterRsrc --keepParent "$staging_dir/QE.app" "dist/$archive"
cd dist
shasum -a 256 "$archive" > SHA256SUMS
printf 'Готово: dist/%s и dist/SHA256SUMS\n' "$archive"
