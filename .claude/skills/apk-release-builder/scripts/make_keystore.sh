#!/usr/bin/env bash
# make_keystore.sh - create (or reuse) the release signing key and wire it up.
#
# The keystore is the single most dangerous file in an Android release: losing
# it means you can never update the app again, and leaking it means anyone can
# publish updates as you. This script keeps it out of git and prints a backup
# reminder.
#
# Usage:
#   make_keystore.sh --project ./android [--alias release] [--cn "Acme Inc"]
#                    [--storepass PASS] [--keypass PASS] [--validity 10950]
#                    [--keystore ./release.keystore] [--force]
set -euo pipefail

PROJECT="."
ALIAS="release"
CN="Release Key"
OU="Mobile"
O="Unknown"
L="Unknown"
ST="Unknown"
C="US"
STOREPASS=""
KEYPASS=""
VALIDITY=10950          # ~30 years; Play requires the key to outlive the app
KEYSTORE=""
FORCE=0

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)    PROJECT="${2:?}"; shift 2 ;;
    --alias)      ALIAS="${2:?}"; shift 2 ;;
    --cn)         CN="${2:?}"; shift 2 ;;
    --ou)         OU="${2:?}"; shift 2 ;;
    --org)        O="${2:?}"; shift 2 ;;
    --city)       L="${2:?}"; shift 2 ;;
    --state)      ST="${2:?}"; shift 2 ;;
    --country)    C="${2:?}"; shift 2 ;;
    --storepass)  STOREPASS="${2:?}"; shift 2 ;;
    --keypass)    KEYPASS="${2:?}"; shift 2 ;;
    --validity)   VALIDITY="${2:?}"; shift 2 ;;
    --keystore)   KEYSTORE="${2:?}"; shift 2 ;;
    --force)      FORCE=1; shift ;;
    -h|--help)    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            die "unknown argument: $1" ;;
  esac
done

command -v keytool >/dev/null 2>&1 || die "keytool not found - a JDK 17+ must be installed (or set JAVA_HOME)."
[[ -d "$PROJECT" ]] || die "project directory not found: $PROJECT"
PROJECT="$(cd "$PROJECT" && pwd)"
KEYSTORE="${KEYSTORE:-$PROJECT/release.keystore}"
[[ "$VALIDITY" =~ ^[0-9]+$ ]] || die "--validity must be an integer number of days"

if [[ -f "$KEYSTORE" && "$FORCE" != "1" ]]; then
  cat <<EOF
Keystore already exists: $KEYSTORE
Reusing it. That is the correct behaviour for app updates - a new key would
make the update uninstallable over the published app.
Use --force to overwrite (only do this for an app that has never been published).
KEYSTORE=$KEYSTORE
EOF
  exit 0
fi

# Random alphanumeric passwords: properties files treat \ : = and # specially,
# so avoid punctuation entirely.
if [[ -z "$STOREPASS" ]]; then
  if command -v openssl >/dev/null 2>&1; then STOREPASS="$(openssl rand -hex 16)"
  else STOREPASS="$(date +%s%N | sha256sum | cut -c1-32)"; fi
fi
[[ -n "$KEYPASS" ]] || KEYPASS="$STOREPASS"

keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 \
  -validity "$VALIDITY" \
  -storepass "$STOREPASS" \
  -keypass "$KEYPASS" \
  -dname "CN=$CN, OU=$OU, O=$O, L=$L, ST=$ST, C=$C" >/dev/null

chmod 600 "$KEYSTORE"

PROPS="$PROJECT/keystore.properties"
cat > "$PROPS" <<EOF
# Release signing configuration - NEVER commit this file.
storeFile=$KEYSTORE
storePassword=$STOREPASS
keyAlias=$ALIAS
keyPassword=$KEYPASS
EOF
chmod 600 "$PROPS"

# Make sure the secrets cannot be committed by accident.
GI="$PROJECT/.gitignore"
touch "$GI"
for entry in "keystore.properties" "*.keystore" "*.jks" "dist/"; do
  grep -qxF "$entry" "$GI" 2>/dev/null || printf '%s\n' "$entry" >> "$GI"
done

cat <<EOF

Release keystore created
  keystore:   $KEYSTORE
  alias:      $ALIAS
  properties: $PROPS   (read automatically by app/build.gradle.kts)
  validity:   $VALIDITY days

  storePassword: $STOREPASS
  keyPassword:   $KEYPASS

BACK THIS UP NOW. Store the keystore + both passwords outside the repository
(password manager, encrypted drive). If you lose them you can never ship an
update to the published app; if they leak, anyone can publish as you.

For Google Play: enable Play App Signing so Google re-signs delivery builds and
you can recover from a lost upload key. See references/play-store-checklist.md.

KEYSTORE=$KEYSTORE
EOF
