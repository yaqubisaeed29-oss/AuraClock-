#!/usr/bin/env bash
# scaffold.sh - generate a complete, buildable Android project from the template.
#
# The template is a framework-only WebView host (no AndroidX, no Kotlin plugin),
# which is the most reliable thing to build from a natural language app idea.
# The actual product is HTML/CSS/JS under app/src/main/assets/www/.
#
# Usage:
#   scaffold.sh --app-name "Aura Clock" --package com.acme.auraclock --out ./android \
#               [--version-code 1] [--version-name 1.0] [--accent "#7C5CFF"] [--bg "#0B0B12"]
#               [--agp 8.13.0] [--gradle 8.13] [--min-sdk 26] [--target-sdk 36]
#               [--compile-sdk 36] [--force]
set -euo pipefail

SKILL_DIR="${CLAUDE_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TEMPLATE="webview"

APP_NAME="My App"
PACKAGE="com.example.myapp"
OUT="./android-app"
VERSION_CODE=1
VERSION_NAME="1.0"
AGP_VERSION="8.13.0"
GRADLE_VERSION="8.13"
COMPILE_SDK=36
TARGET_SDK=36
MIN_SDK=26
ACCENT="#7C5CFF"
BG="#0B0B12"
FORCE=0

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-name)      APP_NAME="${2:?}"; shift 2 ;;
    --package)       PACKAGE="${2:?}"; shift 2 ;;
    --out)           OUT="${2:?}"; shift 2 ;;
    --version-code)  VERSION_CODE="${2:?}"; shift 2 ;;
    --version-name)  VERSION_NAME="${2:?}"; shift 2 ;;
    --agp)           AGP_VERSION="${2:?}"; shift 2 ;;
    --gradle)        GRADLE_VERSION="${2:?}"; shift 2 ;;
    --compile-sdk)   COMPILE_SDK="${2:?}"; shift 2 ;;
    --target-sdk)    TARGET_SDK="${2:?}"; shift 2 ;;
    --min-sdk)       MIN_SDK="${2:?}"; shift 2 ;;
    --accent)        ACCENT="${2:?}"; shift 2 ;;
    --bg)            BG="${2:?}"; shift 2 ;;
    --template)      TEMPLATE="${2:?}"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown argument: $1 (try --help)" ;;
  esac
done

# ------------------------------------------------------------- validation
[[ "$PACKAGE" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] \
  || die "invalid --package '$PACKAGE'. Use reverse DNS, lowercase, at least two segments, no keywords like 'android' as a segment."
[[ "$VERSION_CODE" =~ ^[0-9]+$ ]] || die "--version-code must be a positive integer (Play requires it to increase on every upload)."
[[ "$MIN_SDK" =~ ^[0-9]+$ && "$TARGET_SDK" =~ ^[0-9]+$ && "$COMPILE_SDK" =~ ^[0-9]+$ ]] || die "sdk levels must be integers"
[[ "$ACCENT" =~ ^#[0-9A-Fa-f]{6}$ ]] || die "--accent must be a hex color like #7C5CFF"
[[ "$BG" =~ ^#[0-9A-Fa-f]{6}$ ]] || die "--bg must be a hex color like #0B0B12"
[[ "$MIN_SDK" -ge 26 ]] || printf 'WARNING: minSdk %s < 26 needs real PNG launcher icons; the template ships an adaptive XML icon only.\n' "$MIN_SDK" >&2
[[ "$TARGET_SDK" -ge 36 ]] || printf 'WARNING: targetSdk %s < 36 - Google Play rejects new apps and updates below API 36 since 2026-08-31.\n' "$TARGET_SDK" >&2

TEMPLATE_DIR="$SKILL_DIR/assets/templates/$TEMPLATE"
[[ -d "$TEMPLATE_DIR" ]] || die "template not found: $TEMPLATE_DIR"

if [[ -e "$OUT" && "$FORCE" != "1" ]]; then
  die "$OUT already exists. Re-run with --force to overwrite, or choose another --out."
fi

# ------------------------------------------------------------ derivations
PROJECT_NAME="$(printf '%s' "$APP_NAME" | tr -c 'A-Za-z0-9' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//')"
[[ -n "$PROJECT_NAME" ]] || PROJECT_NAME="app"
# Android string resources: escape XML/Android-sensitive characters.
APP_NAME_XML="$(printf '%s' "$APP_NAME" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e "s/'/\\\\'/g")"
PKG_PATH="${PACKAGE//./\/}"

# ------------------------------------------------------------------ copy
mkdir -p "$OUT"
cp -R "$TEMPLATE_DIR/." "$OUT/"
[[ -f "$OUT/gitignore.tmpl" ]] && mv "$OUT/gitignore.tmpl" "$OUT/.gitignore"

if [[ -d "$OUT/app/src/main/java/PKG_DIR" ]]; then
  mkdir -p "$OUT/app/src/main/java/$PKG_PATH"
  find "$OUT/app/src/main/java/PKG_DIR" -type f -exec mv {} "$OUT/app/src/main/java/$PKG_PATH/" \;
  rm -rf "$OUT/app/src/main/java/PKG_DIR"
fi

# ---------------------------------------------------------- token render
esc() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'; }

E_APP_NAME="$(esc "$APP_NAME")"
E_APP_NAME_XML="$(esc "$APP_NAME_XML")"
E_PROJECT_NAME="$(esc "$PROJECT_NAME")"
E_PACKAGE="$(esc "$PACKAGE")"

render_file() {
  local f="$1" tmp
  tmp="$(mktemp)"
  sed -e "s|@@APP_NAME_XML@@|$E_APP_NAME_XML|g" \
      -e "s|@@APP_NAME@@|$E_APP_NAME|g" \
      -e "s|@@PROJECT_NAME@@|$E_PROJECT_NAME|g" \
      -e "s|@@PACKAGE@@|$E_PACKAGE|g" \
      -e "s|@@VERSION_CODE@@|$VERSION_CODE|g" \
      -e "s|@@VERSION_NAME@@|$VERSION_NAME|g" \
      -e "s|@@AGP_VERSION@@|$AGP_VERSION|g" \
      -e "s|@@GRADLE_VERSION@@|$GRADLE_VERSION|g" \
      -e "s|@@COMPILE_SDK@@|$COMPILE_SDK|g" \
      -e "s|@@TARGET_SDK@@|$TARGET_SDK|g" \
      -e "s|@@MIN_SDK@@|$MIN_SDK|g" \
      -e "s|@@ACCENT_COLOR@@|$ACCENT|g" \
      -e "s|@@BG_COLOR@@|$BG|g" \
      "$f" > "$tmp"
  mv "$tmp" "$f"
}

while IFS= read -r -d '' f; do
  render_file "$f"
done < <(find "$OUT" -type f \
  \( -name '*.kts' -o -name '*.gradle' -o -name '*.xml' -o -name '*.java' \
     -o -name '*.kt' -o -name '*.html' -o -name '*.css' -o -name '*.js' \
     -o -name '*.properties' -o -name '*.pro' -o -name '*.md' -o -name '*.yml' \
     -o -name '*.yaml' -o -name '*.tmpl' \) -print0)

# Fail loudly if any placeholder survived.
if grep -rl '@@' "$OUT" >/dev/null 2>&1; then
  printf 'ERROR: unrendered placeholders remain:\n' >&2
  grep -rl '@@' "$OUT" >&2
  exit 1
fi

# ------------------------------------------------- local.properties / sdk
SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$SDK_DIR" ]]; then
  for candidate in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/usr/lib/android-sdk" "/opt/android-sdk"; do
    [[ -d "$candidate" ]] && SDK_DIR="$candidate" && break
  done
fi
if [[ -n "$SDK_DIR" && -d "$SDK_DIR" && ! -f "$OUT/local.properties" ]]; then
  printf 'sdk.dir=%s\n' "$(printf '%s' "$SDK_DIR" | sed 's/\\:/g; s/:/\\\\:/g')" > "$OUT/local.properties"
fi

mkdir -p "$OUT/dist"

# ---------------------------------------------------------------- output
cat <<EOF

Scaffolded Android project
  dir:            $OUT
  app name:       $APP_NAME
  applicationId:  $PACKAGE
  version:        $VERSION_NAME (versionCode $VERSION_CODE)
  sdk:            compile $COMPILE_SDK / target $TARGET_SDK / min $MIN_SDK
  toolchain:      AGP $AGP_VERSION + Gradle $GRADLE_VERSION (JDK 17+)

Next steps
  1. Write the product into $OUT/app/src/main/assets/www/  (index.html is the entry point)
  2. scripts/make_keystore.sh --project $OUT          # release signing key
  3. scripts/build_release.sh --project $OUT          # APK + AAB into $OUT/dist/
  4. scripts/verify_release.sh --project $OUT         # signature + badging report

PROJECT_DIR=$OUT
PACKAGE=$PACKAGE
EOF
