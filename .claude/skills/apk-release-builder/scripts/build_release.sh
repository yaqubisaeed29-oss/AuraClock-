#!/usr/bin/env bash
# build_release.sh - produce signed release artifacts: APK (sideload) + AAB (Play).
#
# Google Play requires an .aab for new apps; the .apk is what you hand to a
# tester or install with adb. This builds both and copies them to dist/ with
# useful filenames.
#
# Usage:
#   build_release.sh --project ./android [--apk-only|--aab-only] [--no-clean]
#                    [--debug] [--gradle-args "--info"]
set -euo pipefail

PROJECT="."
BUILD_APK=1
BUILD_AAB=1
CLEAN=1
VARIANT="release"
EXTRA_ARGS=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)      PROJECT="${2:?}"; shift 2 ;;
    --apk-only)     BUILD_AAB=0; shift ;;
    --aab-only)     BUILD_APK=0; shift ;;
    --no-clean)     CLEAN=0; shift ;;
    --debug)        VARIANT="debug"; shift ;;
    --gradle-args)  EXTRA_ARGS="${2:?}"; shift 2 ;;
    -h|--help)      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[[ -d "$PROJECT" ]] || die "project not found: $PROJECT"
cd "$PROJECT"
if [[ ! -f settings.gradle.kts && ! -f settings.gradle ]]; then
  die "no Gradle settings file in $(pwd) - is --project pointing at the Android project root?"
fi
if [[ ! -f app/build.gradle.kts && ! -f app/build.gradle ]]; then
  die "no app module build file in $(pwd)/app - the project looks incomplete."
fi

# ------------------------------------------------------------------- SDK
SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$SDK_DIR" ]]; then
  for candidate in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/usr/lib/android-sdk" "/opt/android-sdk" "/opt/android/sdk"; do
    [[ -d "$candidate" ]] && SDK_DIR="$candidate" && break
  done
fi
[[ -n "$SDK_DIR" && -d "$SDK_DIR" ]] || die "Android SDK not found. Set ANDROID_HOME, install the SDK (references/environment-routes.md route A2), build with Docker (route B), or build in CI (route C)."
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
[[ -f local.properties ]] || printf 'sdk.dir=%s\n' "$(printf '%s' "$SDK_DIR" | sed 's/:/\\\\:/g')" > local.properties

# ------------------------------------------------------------------ JDK
if command -v java >/dev/null 2>&1; then
  JAVA_MAJOR="$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+)(\.([0-9]+))?.*/\1 \3/' | awk '{ if ($1 == 1) print $2; else print $1 }')"
  [[ "$JAVA_MAJOR" =~ ^[0-9]+$ ]] || JAVA_MAJOR=0
  [[ "$JAVA_MAJOR" -ge 17 ]] || die "Gradle needs JDK 17+ (found $JAVA_MAJOR). Install Temurin 17/21 or set org.gradle.java.home in gradle.properties."
else
  die "java not found - install JDK 17+ first."
fi

# -------------------------------------------------------------- wrapper
WRAPPER_VERSION="$(sed -nE 's#.*gradle-(.+)-bin\.zip#\1#p' gradle/wrapper/gradle-wrapper.properties 2>/dev/null | head -1)"
WRAPPER_VERSION="${WRAPPER_VERSION:-8.13}"
if [[ ! -f gradlew || ! -f gradle/wrapper/gradle-wrapper.jar ]]; then
  echo "Gradle wrapper jar is missing - bootstrapping with a local Gradle ($WRAPPER_VERSION)."
  command -v gradle >/dev/null 2>&1 \
    || die "no ./gradlew, no gradle/wrapper/gradle-wrapper.jar and no 'gradle' on PATH. Install Gradle, or use the CI route (scripts/ci_workflow.sh) where the runner bootstraps it."
  gradle wrapper --gradle-version "$WRAPPER_VERSION" --distribution-type bin
fi
chmod +x gradlew 2>/dev/null || true

# ---------------------------------------------------------------- build
TASKS=()
[[ "$CLEAN" == "1" ]] && TASKS+=("clean")
if [[ "$VARIANT" == "release" ]]; then
  [[ "$BUILD_APK" == "1" ]] && TASKS+=("assembleRelease")
  [[ "$BUILD_AAB" == "1" ]] && TASKS+=("bundleRelease")
else
  TASKS+=("assembleDebug")
fi

echo "Running: ./gradlew ${TASKS[*]} $EXTRA_ARGS"
./gradlew --no-daemon --stacktrace "${TASKS[@]}" $EXTRA_ARGS

# ------------------------------------------------------------- artifacts
APP_NAME="$(sed -nE 's#.*<string name="app_name">(.*)</string>.*#\1#p' app/src/main/res/values/strings.xml 2>/dev/null | head -1 || true)"
[[ -n "$APP_NAME" ]] || APP_NAME="app"
SLUG="$(printf '%s' "$APP_NAME" | tr -c 'A-Za-z0-9' '-' | sed -E 's/-+/-/g; s/^-//; s/-$//' | tr 'A-Z' 'a-z')"
[[ -n "$SLUG" ]] || SLUG="app"
VERSION_NAME="$(sed -nE 's/.*versionName[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' app/build.gradle.kts app/build.gradle 2>/dev/null | head -1 || true)"
VERSION_CODE="$(sed -nE 's/.*versionCode[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' app/build.gradle.kts app/build.gradle 2>/dev/null | head -1 || true)"
VERSION_NAME="${VERSION_NAME:-1.0}"
VERSION_CODE="${VERSION_CODE:-1}"

mkdir -p dist
collect() { # <src> <dst>
  [[ -f "$1" ]] || return 1
  cp -f "$1" "$2"
  local size sha
  size="$(du -h "$2" | cut -f1)"
  if command -v sha256sum >/dev/null 2>&1; then sha="$(sha256sum "$2" | cut -d' ' -f1)"
  else sha="$(shasum -a 256 "$2" | cut -d' ' -f1)"; fi
  printf 'ARTIFACT=%s\nSIZE=%s\nSHA256=%s\n' "$2" "$size" "$sha"
}

echo ""
echo "================ build output ================"
STATUS=0
if [[ "$BUILD_APK" == "1" || "$VARIANT" == "debug" ]]; then
  SRC_APK="app/build/outputs/apk/$VARIANT/app-$VARIANT.apk"
  [[ -f "$SRC_APK" ]] || SRC_APK="$(find app/build/outputs/apk -name '*.apk' 2>/dev/null | head -1)"
  if [[ -n "${SRC_APK:-}" && -f "${SRC_APK:-}" ]]; then
    collect "$SRC_APK" "dist/$SLUG-$VERSION_NAME-$VERSION_CODE-$VARIANT.apk" || STATUS=1
  else
    echo "ERROR: no APK produced"; STATUS=1
  fi
fi
if [[ "$BUILD_AAB" == "1" && "$VARIANT" == "release" ]]; then
  SRC_AAB="app/build/outputs/bundle/release/app-release.aab"
  [[ -f "$SRC_AAB" ]] || SRC_AAB="$(find app/build/outputs/bundle -name '*.aab' 2>/dev/null | head -1)"
  if [[ -n "${SRC_AAB:-}" && -f "${SRC_AAB:-}" ]]; then
    collect "$SRC_AAB" "dist/$SLUG-$VERSION_NAME-$VERSION_CODE-release.aab" || STATUS=1
  else
    echo "ERROR: no AAB produced"; STATUS=1
  fi
fi
echo "=============================================="

# Warn when the release build fell back to the debug signature.
if [[ "$VARIANT" == "release" && ! -f keystore.properties && -z "${RELEASE_STORE_PASSWORD:-}" ]]; then
  cat <<'EOF'

WARNING: no keystore.properties and no RELEASE_* environment variables were
found, so this artifact is signed with the DEBUG key. It installs on a device
for testing, but it is NOT publishable - Google Play rejects debug-signed
uploads, and it cannot be updated later by a properly signed build.
Run scripts/make_keystore.sh --project . and rebuild.
EOF
fi

exit "$STATUS"
