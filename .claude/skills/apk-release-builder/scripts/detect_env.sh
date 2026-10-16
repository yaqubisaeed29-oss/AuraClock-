#!/usr/bin/env bash
# detect_env.sh - report what this machine can actually build, and pick a route.
#
# Usage:
#   detect_env.sh            human readable report + ROUTE= line
#   detect_env.sh --kv       machine readable KEY=VALUE only
#
# Exit code is always 0 unless the script itself fails; the verdict is in ROUTE.
set -uo pipefail

KV_ONLY=0
[[ "${1:-}" == "--kv" ]] && KV_ONLY=1

have() { command -v "$1" >/dev/null 2>&1; }

say() { [[ "$KV_ONLY" == "1" ]] || printf '%s\n' "$*"; }
kv()  { printf '%s=%s\n' "$1" "$2"; }

# ------------------------------------------------------------------ java
JAVA_OK=0
JAVA_MAJOR=0
if have java; then
  JAVA_VERSION_RAW="$(java -version 2>&1 | head -1)"
  JAVA_MAJOR="$(printf '%s' "$JAVA_VERSION_RAW" | sed -E 's/.*version "([0-9]+)(\.([0-9]+))?.*/\1 \3/' | awk '{ if ($1 == 1) print $2; else print $1 }')"
  [[ "$JAVA_MAJOR" =~ ^[0-9]+$ ]] || JAVA_MAJOR=0
  if [[ "$JAVA_MAJOR" -ge 17 ]]; then JAVA_OK=1; fi
else
  JAVA_VERSION_RAW="not installed"
fi
kv JAVA_PRESENT "$(have java && echo 1 || echo 0)"
kv JAVA_MAJOR "$JAVA_MAJOR"
kv JAVA_17_PLUS "$JAVA_OK"
say "java:            $JAVA_VERSION_RAW"

# Gradle only matters for bootstrapping a missing wrapper.
if have gradle; then
  GRADLE_VERSION_RAW="$(gradle --version 2>/dev/null | awk -F': ' '/^Gradle /{print $2; exit}')"
else
  GRADLE_VERSION_RAW="not installed"
fi
kv GRADLE_PRESENT "$(have gradle && echo 1 || echo 0)"
say "gradle:          $GRADLE_VERSION_RAW"

# ------------------------------------------------------- android sdk
SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$SDK_DIR" ]]; then
  for candidate in \
      "$HOME/Android/Sdk" \
      "$HOME/Library/Android/sdk" \
      "/usr/lib/android-sdk" \
      "/opt/android-sdk" \
      "/opt/android/sdk" \
      "$HOME/android-sdk"; do
    if [[ -d "$candidate" ]]; then SDK_DIR="$candidate"; break; fi
  done
fi

SDK_OK=0
SDKMANAGER_OK=0
BUILD_TOOLS_OK=0
PLATFORMS_OK=0
if [[ -n "$SDK_DIR" && -d "$SDK_DIR" ]]; then
  SDK_OK=1
  if [[ -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]] || have sdkmanager; then SDKMANAGER_OK=1; fi
  if compgen -G "$SDK_DIR/build-tools/*" >/dev/null 2>&1; then BUILD_TOOLS_OK=1; fi
  if compgen -G "$SDK_DIR/platforms/android-*" >/dev/null 2>&1; then PLATFORMS_OK=1; fi
fi
kv ANDROID_SDK_DIR "$SDK_DIR"
kv ANDROID_SDK_PRESENT "$SDK_OK"
kv SDKMANAGER_PRESENT "$SDKMANAGER_OK"
kv BUILD_TOOLS_PRESENT "$BUILD_TOOLS_OK"
kv PLATFORMS_PRESENT "$PLATFORMS_OK"
say "android sdk:     ${SDK_DIR:-not found} (build-tools=$BUILD_TOOLS_OK platforms=$PLATFORMS_OK sdkmanager=$SDKMANAGER_OK)"

# ------------------------------------------------------------- other tools
kv DOCKER_PRESENT "$(have docker && docker info >/dev/null 2>&1 && echo 1 || echo 0)"
kv GIT_PRESENT "$(have git && echo 1 || echo 0)"
kv GH_PRESENT "$(have gh && echo 1 || echo 0)"
kv ZIP_PRESENT "$(have zip && echo 1 || echo 0)"
say "docker:          $(have docker && echo yes || echo no)   git: $(have git && echo yes || echo no)   gh: $(have gh && echo yes || echo no)"

# ---------------------------------------------------------------- network
probe() {
  curl -fsS -m 6 -o /dev/null "$1" >/dev/null 2>&1 && echo 1 || echo 0
}
NET_GOOGLE="$(probe https://dl.google.com/android/repository/repository2-3.xml)"
NET_MAVEN="$(probe https://repo.maven.apache.org/maven2/)"
NET_GRADLE="$(probe https://services.gradle.org/distributions/)"
NET_GITHUB="$(probe https://api.github.com/)"
kv NET_DL_GOOGLE "$NET_GOOGLE"
kv NET_MAVEN_CENTRAL "$NET_MAVEN"
kv NET_SERVICES_GRADLE "$NET_GRADLE"
kv NET_GITHUB "$NET_GITHUB"
say "network:         dl.google.com=$NET_GOOGLE maven=$NET_MAVEN gradle-dist=$NET_GRADLE github=$NET_GITHUB"

[[ "$NET_GOOGLE" == "1" && "$NET_MAVEN" == "1" ]] && NET_DEPS=1 || NET_DEPS=0
kv NET_DEPS_REACHABLE "$NET_DEPS"

# ------------------------------------------------------------------ disk
FREE_KB="$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4}')"
FREE_GB="$(( ${FREE_KB:-0} / 1024 / 1024 ))"
kv FREE_DISK_GB "$FREE_GB"
say "free disk:       ${FREE_GB} GB"

# ----------------------------------------------------------------- route
# A: build right here (JDK 17+ and a usable SDK, or SDK installable online)
# B: build in a container (docker daemon + network)
# C: build in CI (git/gh + network to github)
# D: hand off a ready-to-build project archive (nothing else works)
ROUTE="D"
if [[ "$JAVA_OK" == "1" && "$NET_DEPS" == "1" ]]; then
  if [[ "$PLATFORMS_OK" == "1" && "$BUILD_TOOLS_OK" == "1" ]]; then
    ROUTE="A"
  elif [[ "$SDKMANAGER_OK" == "1" || "$SDK_OK" == "0" ]]; then
    ROUTE="A_INSTALL_SDK"   # route A after installing cmdline-tools + packages
  fi
fi
if [[ "$ROUTE" == "D" && "${DOCKER:-0}" == "0" ]]; then
  if have docker && docker info >/dev/null 2>&1 && [[ "$NET_DEPS" == "1" ]]; then ROUTE="B"; fi
fi
if [[ "$ROUTE" == "D" && "$NET_GITHUB" == "1" ]]; then ROUTE="C"; fi

kv ROUTE "$ROUTE"
say ""
say "ROUTE=$ROUTE"
case "$ROUTE" in
  A)            say "  -> Build locally: ./gradlew assembleRelease bundleRelease works as-is." ;;
  A_INSTALL_SDK) say "  -> Build locally after installing the SDK: see references/environment-routes.md route A2." ;;
  B)            say "  -> No local toolchain. Build inside the provided Dockerfile (route B)." ;;
  C)            say "  -> Sandboxed/offline for Android deps. Emit the GitHub Actions workflow and build in CI (route C)." ;;
  D)            say "  -> Nothing can build here. Package the project for handoff (route D) and tell the user the exact commands." ;;
esac
