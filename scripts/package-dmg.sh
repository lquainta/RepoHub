#!/usr/bin/env bash
# Builds RepoHub for release and packages it as a DMG for GitHub Releases (#44).
#
#   scripts/package-dmg.sh [version]
#
# - Builds the Release configuration as a universal app (Apple silicon and Intel).
# - Signs it ad hoc. There's no Developer ID, so it isn't notarized: Gatekeeper
#   asks the user to allow it on first launch (see README, "Install").
# - Packages it in a compressed DMG with a link to /Applications, so it can be
#   dragged in, and writes a SHA-256 checksum next to it.
#
# The version defaults to MARKETING_VERSION in App/project.yml. Output goes to
# $OUT_DIR (default build/dist): RepoHub-<version>.dmg and .dmg.sha256.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:-$(sed -nE 's/.*MARKETING_VERSION: "([^"]+)".*/\1/p' App/project.yml)}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "error: '$version' isn't a version like 1.2.3" >&2
  exit 1
fi
out="${OUT_DIR:-build/dist}"
derived="build/release-DerivedData"
dmg="$out/RepoHub-$version.dmg"

make generate
echo "Building RepoHub $version (Release, universal)…"
xcodebuild -project App/RepoHub.xcodeproj -scheme RepoHub -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
  -quiet -skipPackagePluginValidation \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build
app="$derived/Build/Products/Release/RepoHub.app"

# Xcode signs ad hoc already (CODE_SIGN_IDENTITY "-"). Sign the whole bundle
# again so every nested binary is covered, with the hardened runtime: Apple
# silicon refuses to launch unsigned code.
codesign --force --deep --options runtime --sign - "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/RepoHub" -verify_arch arm64 x86_64
built_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
# release-please writes the version into App/project.yml, so a mismatch means
# the tag and the source disagree.
if [[ "$built_version" != "$version" ]]; then
  echo "error: the app says it's $built_version, expected $version" >&2
  exit 1
fi

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"

mkdir -p "$out"
rm -f "$dmg" "$dmg.sha256"
hdiutil create -volname "RepoHub $version" -srcfolder "$staging" -fs HFS+ -format UDZO -quiet "$dmg"
hdiutil verify -quiet "$dmg"
(cd "$out" && shasum -a 256 "RepoHub-$version.dmg" >"RepoHub-$version.dmg.sha256")

echo "$dmg"
cat "$dmg.sha256"
