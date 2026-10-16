#!/usr/bin/env bash
# package_project.sh - zip a generated project so the user can take it away.
#
# This is the deliverable when the current environment cannot compile anything
# (no JDK / no Android SDK / no network to Google). The archive contains the
# full source, the CI workflow and a BUILD.md with exact commands.
#
# Usage:
#   package_project.sh --project ./android [--out ./dist] [--name my-app-src.zip]
set -euo pipefail

PROJECT="."
OUT=""
NAME=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --out)     OUT="${2:?}"; shift 2 ;;
    --name)    NAME="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown argument: $1" ;;
  esac
done

[[ -d "$PROJECT" ]] || die "project not found: $PROJECT"
PROJECT="$(cd "$PROJECT" && pwd)"
PARENT="$(dirname "$PROJECT")"
BASE="$(basename "$PROJECT")"
OUT="${OUT:-$PARENT}"
NAME="${NAME:-$BASE-src.zip}"

command -v zip >/dev/null 2>&1 || die "zip is not installed"
mkdir -p "$OUT"
ARCHIVE="$OUT/$NAME"
rm -f "$ARCHIVE"

# Never ship secrets or build output.
cd "$PARENT"
zip -qr "$ARCHIVE" "$BASE" \
  -x "$BASE/.gradle/*" \
  -x "$BASE/**/build/*" \
  -x "$BASE/build/*" \
  -x "$BASE/dist/*" \
  -x "$BASE/local.properties" \
  -x "$BASE/keystore.properties" \
  -x "$BASE/*.keystore" \
  -x "$BASE/*.jks" \
  -x "$BASE/.git/*"

if unzip -l "$ARCHIVE" 2>/dev/null | grep -qE 'keystore\.properties|\.(keystore|jks)$'; then
  rm -f "$ARCHIVE"
  die "refusing to package signing secrets - remove them from $PROJECT first"
fi

echo "ARCHIVE=$ARCHIVE"
echo "SIZE=$(du -h "$ARCHIVE" | cut -f1)"
echo "ENTRIES=$(unzip -l "$ARCHIVE" 2>/dev/null | tail -1 | awk '{print $2}')"
