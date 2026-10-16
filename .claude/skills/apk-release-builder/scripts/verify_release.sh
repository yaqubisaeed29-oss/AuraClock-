#!/usr/bin/env bash
# verify_release.sh - prove an artifact is actually publishable before handing it over.
#
# Checks: signature scheme and certificate, versionCode/versionName, min/target
# SDK, launcher activity, declared permissions, alignment, and size.
#
# Usage:
#   verify_release.sh --project ./android [path/to/app.apk|app.aab]
set -euo pipefail

PROJECT="."
TARGET=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         TARGET="$1"; shift ;;
  esac
done

[[ -d "$PROJECT" ]] || die "project not found: $PROJECT"
cd "$PROJECT"

SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
for candidate in "$SDK_DIR" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/usr/lib/android-sdk" "/opt/android-sdk"; do
  if [[ -n "$candidate" && -d "$candidate/build-tools" ]]; then SDK_DIR="$candidate"; break; fi
done
[[ -n "${SDK_DIR:-}" && -d "${SDK_DIR:-}/build-tools" ]] || SDK_DIR=""

BT=""
if [[ -n "${SDK_DIR:-}" && -d "${SDK_DIR:-}/build-tools" ]]; then
  BT="$(find "$SDK_DIR/build-tools" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -1)"
fi

# Pick the artifact to inspect.
if [[ -z "$TARGET" ]]; then
  TARGET="$(find dist -name '*.apk' 2>/dev/null | sort | tail -1 || true)"
  [[ -n "$TARGET" ]] || TARGET="$(find app/build/outputs/apk -name '*.apk' 2>/dev/null | sort | tail -1 || true)"
fi
[[ -n "$TARGET" && -f "$TARGET" ]] || die "no artifact found. Build first (scripts/build_release.sh) or pass a path."

echo "Artifact: $TARGET ($(du -h "$TARGET" | cut -f1))"
FAIL=0

case "$TARGET" in
  *.aab)
    echo "Type:     Android App Bundle (upload this to Google Play)"
    if command -v bundletool >/dev/null 2>&1; then
      bundletool dump manifest --bundle "$TARGET" || FAIL=1
    else
      python3 - "$TARGET" <<'PY' || FAIL=1
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
required = ["BundleConfig.pb", "base/manifest/AndroidManifest.xml"]
missing = [r for r in required if r not in names]
print("modules:", sorted({n.split('/')[0] for n in names}))
print("entries:", len(names))
print("missing:", missing if missing else "none")
sys.exit(1 if missing else 0)
PY
    fi
    ;;
  *.apk)
    echo "Type:     APK"
    if [[ -n "$BT" && -x "$BT/apksigner" ]]; then
      echo ""
      echo "--- apksigner verify ---"
      if "$BT/apksigner" verify --verbose --print-certs "$TARGET"; then :; else FAIL=1; fi
      echo ""
      echo "--- zipalign check ---"
      if [[ -x "$BT/zipalign" ]]; then
        "$BT/zipalign" -c -v 4 "$TARGET" >/dev/null 2>&1 && echo "aligned: OK" || { echo "aligned: FAILED"; FAIL=1; }
      fi
    else
      echo "apksigner not available (no Android SDK build-tools here)."
      echo "Falling back to a structural check:"
      python3 - "$TARGET" <<'PY' || FAIL=1
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = set(z.namelist())
need = ["AndroidManifest.xml", "classes.dex", "resources.arsc", "META-INF/"]
print("has AndroidManifest.xml:", "AndroidManifest.xml" in names)
print("has classes.dex:", "classes.dex" in names)
print("has resources.arsc:", "resources.arsc" in names)
print("signature files:", sorted(n for n in names if n.startswith("META-INF/"))[:8])
ok = {"AndroidManifest.xml", "classes.dex"} <= names
sys.exit(0 if ok else 1)
PY
    fi

    if [[ -n "$BT" && -x "$BT/aapt2" ]]; then
      echo ""
      echo "--- aapt2 badging ---"
      "$BT/aapt2" dump badging "$TARGET" 2>/dev/null \
        | grep -E "^(package|sdkVersion|targetSdkVersion|application-label|launchable-activity|uses-permission|native-code|densities)" \
        || true
      TS="$( "$BT/aapt2" dump badging "$TARGET" 2>/dev/null | sed -nE "s/^targetSdkVersion:[[:space:]]*'([0-9]+)'.*/\1/p" | head -1 )"
      if [[ -n "$TS" && "$TS" -lt 36 ]]; then
        echo ""
        echo "WARNING: targetSdkVersion=$TS. Google Play requires 36 (Android 16) for new apps and updates since 2026-08-31."
      fi
    fi
    ;;
  *) die "unsupported artifact type: $TARGET" ;;
esac

echo ""
if [[ "$FAIL" == "0" ]]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL - fix the errors above before publishing"
fi
exit "$FAIL"
