#!/usr/bin/env bash
# Publishes a new Android version as a GitHub release, the one Obtainium
# picks up and installs on the phone, and then the web on the same version.
#   scripts/release.sh          bumps the last number: 5.5.0 -> 5.5.1
#   scripts/release.sh 5.6.0    sets the version by hand
# Needs a clean working tree, Flutter in the PATH and gh logged in with an
# account that can write to the repo.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/budget"
repo="AndersonDavi/finza-colombia"

if [ -n "$(git -C "$root" status --porcelain --untracked-files=no)" ]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi

current=$(sed -n 's/^version: //p' "$app/pubspec.yaml")
name=${current%+*}
build=${current#*+}
if [ $# -ge 1 ]; then
  next=$1
else
  IFS=. read -r major minor patch <<< "$name"
  next="$major.$minor.$((patch + 1))"
fi
# Android only installs over the old one when this number goes up
next_build=$((build + 1))
previous=$(git -C "$root" describe --tags --abbrev=0 --match "v*" 2>/dev/null || true)

sed -i "s/^version: .*/version: $next+$next_build/" "$app/pubspec.yaml"
if ! (cd "$app" && flutter build apk --release --target-platform android-arm64); then
  git -C "$root" checkout -- budget/pubspec.yaml
  exit 1
fi

apk="$app/build/finza-$next.apk"
cp "$app/build/app/outputs/flutter-apk/app-release.apk" "$apk"
if [ -n "$previous" ]; then
  notes=$(git -C "$root" log --format="- %s" "$previous..HEAD")
else
  notes="First release."
fi

git -C "$root" commit -q -m "Version $next" -- budget/pubspec.yaml
git -C "$root" tag "v$next"
git -C "$root" push -q origin HEAD "v$next"
gh release create "v$next" "$apk" --repo "$repo" --title "$next" \
  --notes "${notes:-No changes besides the version.}"
echo "Published $next"

if ! "$root/scripts/deploy-web.sh"; then
  echo "The APK is out, but the web did not publish: run scripts/deploy-web.sh" >&2
  exit 1
fi
