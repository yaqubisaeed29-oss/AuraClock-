#!/usr/bin/env bash
# ci_workflow.sh - emit a GitHub Actions workflow that builds the signed APK/AAB.
#
# Use this when the current machine cannot build (no JDK, no Android SDK, or no
# network to dl.google.com - which is the normal situation inside a chat
# sandbox). The user pushes the project and downloads the artifact, or the
# workflow publishes a GitHub Release on a version tag.
#
# Usage:
#   ci_workflow.sh --project ./android [--name android-release.yml] [--print-secrets]
set -euo pipefail

SKILL_DIR="${CLAUDE_SKILL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT="."
WF_NAME="android-release.yml"
PRINT_SECRETS=1

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --name)    WF_NAME="${2:?}"; shift 2 ;;
    --no-secrets-help) PRINT_SECRETS=0; shift ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown argument: $1" ;;
  esac
done

[[ -d "$PROJECT" ]] || die "project not found: $PROJECT"
ASSET="$SKILL_DIR/assets/ci/android-release.yml"
[[ -f "$ASSET" ]] || die "workflow template missing: $ASSET"
cd "$PROJECT"

GRADLE_VERSION="$(sed -nE 's#.*gradle-(.+)-bin\.zip#\1#p' gradle/wrapper/gradle-wrapper.properties 2>/dev/null | head -1)"
GRADLE_VERSION="${GRADLE_VERSION:-8.13}"
# Reads tolerate a missing Groovy/Kotlin DSL counterpart: `|| true` because
# pipefail would otherwise abort when only one of the two files exists.
PROJECT_NAME="$(sed -nE 's/rootProject\.name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' settings.gradle.kts settings.gradle 2>/dev/null | head -1 || true)"
PROJECT_NAME="${PROJECT_NAME:-app}"
COMPILE_SDK="$(sed -nE 's/.*compileSdk[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' app/build.gradle.kts app/build.gradle 2>/dev/null | head -1 || true)"
COMPILE_SDK="${COMPILE_SDK:-36}"

mkdir -p .github/workflows
sed -e "s|@@GRADLE_VERSION@@|$GRADLE_VERSION|g" \
    -e "s|@@PROJECT_NAME@@|$PROJECT_NAME|g" \
    -e "s|@@COMPILE_SDK@@|$COMPILE_SDK|g" \
    "$ASSET" > ".github/workflows/$WF_NAME"

cat <<EOF
Wrote .github/workflows/$WF_NAME
  gradle:     $GRADLE_VERSION
  compileSdk: $COMPILE_SDK
  artifacts:  APK + AAB uploaded as the "android-release" workflow artifact,
              and attached to a GitHub Release when you push a v* tag.
EOF

if [[ "$PRINT_SECRETS" == "1" ]]; then
  cat <<'EOF'

Signing secrets (skip only if a debug-signed test build is enough):
  # macOS: base64 -i release.keystore | pbcopy
  # Linux: base64 -w0 release.keystore
  gh secret set RELEASE_KEYSTORE_B64    --body "<base64 of release.keystore>"
  gh secret set RELEASE_STORE_PASSWORD  --body "<store password>"
  gh secret set RELEASE_KEY_ALIAS       --body "release"
  gh secret set RELEASE_KEY_PASSWORD    --body "<key password>"

Then:
  git add . && git commit -m "Add Android project and release workflow"
  git push origin HEAD
  # build on demand:
  gh workflow run android-release.yml
  # or tag a release:
  git tag v1.0 && git push origin v1.0
EOF
fi
