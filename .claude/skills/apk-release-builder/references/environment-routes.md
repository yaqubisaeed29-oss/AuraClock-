# Environment routes

Pick the route from `scripts/detect_env.sh` (`ROUTE=`). Every route ends with a
signed APK + AAB or with an archive the user can build elsewhere.

---

## Route A - build locally (toolchain present)

Requirements: JDK 17+, Android SDK with `platforms;android-36` and
`build-tools;36.0.0`, network to `dl.google.com` and `repo.maven.apache.org`
(the first build downloads ~300 MB of Gradle + AGP).

```bash
scripts/scaffold.sh --app-name "X" --package com.acme.x --out ./android
scripts/make_keystore.sh --project ./android --cn "Your Name"
scripts/build_release.sh --project ./android
scripts/verify_release.sh --project ./android
```

Outputs land in `./android/dist/`. First run is slow (dependency download);
later runs are fast thanks to `org.gradle.caching=true`.

If the user already has Android Studio open on the project, the equivalent is
**Build > Generate Signed App Bundle / APK**, or:

```bash
cd android && ./gradlew --no-daemon clean assembleRelease bundleRelease
```

### Missing wrapper jar

`gradle/wrapper/gradle-wrapper.jar` is a binary and is not part of this skill's
template (skills should stay text-only). `build_release.sh` bootstraps it with a
locally installed Gradle. If `gradle` is not installed either:

```bash
# macOS
brew install gradle
# Linux (Debian/Ubuntu)
sudo apt-get install -y gradle      # any recent version works for bootstrapping
# then, inside the project:
gradle wrapper --gradle-version 8.13 --distribution-type bin
```

Commit `gradlew`, `gradlew.bat` and `gradle/wrapper/*` afterwards so CI and
teammates do not need a local Gradle.

---

## Route A2 - install the toolchain, then route A

Fastest on a machine with admin rights. Total ~2 GB, 5-10 minutes.

**JDK 17+**

```bash
# macOS
brew install --cask temurin@17
# Debian/Ubuntu
sudo apt-get install -y temurin-17-jdk      # or: openjdk-17-jdk
# Windows (PowerShell)
winget install EclipseAdoptium.Temurin.17.JDK
java -version   # must print 17 or higher
```

**Android command line tools (no Android Studio needed)**

Get the current archive name from
https://developer.android.com/studio#command-line-tools-only (the numeric id in
the filename changes over time).

```bash
export ANDROID_HOME="$HOME/Android/Sdk"          # macOS/Linux
mkdir -p "$ANDROID_HOME/cmdline-tools"
cd /tmp
curl -fsSLO https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q commandlinetools-linux-*_latest.zip -d "$ANDROID_HOME/cmdline-tools"
mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"

yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
    "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

macOS uses `commandlinetools-mac-*_latest.zip` and
`ANDROID_HOME="$HOME/Library/Android/sdk"`; Windows uses
`commandlinetools-win-*_latest.zip` and
`%LOCALAPPDATA%\Android\Sdk`.

Persist `ANDROID_HOME` in `~/.bashrc` / `~/.zshrc` / system environment, then
re-run `scripts/detect_env.sh` and continue with route A.

**If Android Studio is already installed** the SDK is at
`~/Library/Android/sdk` (macOS), `~/Android/Sdk` (Linux) or
`%LOCALAPPDATA%\Android\Sdk` (Windows). Just export `ANDROID_HOME` and install
the missing packages through **SDK Manager** or `sdkmanager`.

---

## Route B - build in a container

Use when Docker works but the host has no JDK/SDK. The image installs the SDK
once; after that builds are offline-friendly.

```bash
cp <skill>/assets/docker/Dockerfile.android ./Dockerfile.android
docker build -t apk-builder -f Dockerfile.android .

# unsigned/debug build
docker run --rm -v "$PWD/android":/project -w /project apk-builder \
  ./gradlew --no-daemon clean assembleRelease bundleRelease

# signed build: mount the keystore and point keystore.properties at /keys/...
docker run --rm \
  -v "$PWD/android":/project \
  -v "$PWD/android/release.keystore":/keys/release.keystore:ro \
  -w /project apk-builder \
  ./gradlew --no-daemon clean assembleRelease bundleRelease
```

With the mounted-keystore variant, `keystore.properties` inside the project must
contain `storeFile=/keys/release.keystore` (container path, not host path).

---

## Route C - build in GitHub Actions

The default in a chat sandbox: no JDK, no SDK, no route to Google's Maven, but
GitHub is reachable. The runner has the JDK, installs the SDK, and has full
network.

```bash
scripts/scaffold.sh --app-name "X" --package com.acme.x --out ./android
# write the app into ./android/app/src/main/assets/www/
scripts/ci_workflow.sh --project ./android      # writes .github/workflows/android-release.yml
scripts/make_keystore.sh --project ./android    # only if keytool/JDK exist locally
scripts/package_project.sh --project ./android  # -> android-src.zip for the user
```

Then, for the user (or run it yourself when `gh` is authenticated and the repo
is already on GitHub):

```bash
cd android && git init -b main && git add . && git commit -m "Android project + release CI"
gh repo create my-app --private --source=. --push
gh secret set RELEASE_KEYSTORE_B64   --body "$(base64 -w0 release.keystore)"   # macOS: base64 -i
gh secret set RELEASE_STORE_PASSWORD --body "<store password>"
gh secret set RELEASE_KEY_ALIAS      --body "release"
gh secret set RELEASE_KEY_PASSWORD   --body "<key password>"
gh workflow run android-release.yml
gh run watch
gh run download --name android-release --dir ./dist
```

Pushing a `v*` tag additionally publishes a GitHub Release with the APK/AAB
attached, which is a convenient public download link for testers.

**Without signing secrets** the workflow still succeeds and produces a
debug-signed APK: fine for a functional test, not publishable. Say so.

---

## Route D - handoff bundle

Nothing can build: no JDK, no SDK, no Docker, no GitHub. Still deliver
something complete.

```bash
scripts/scaffold.sh --app-name "X" --package com.acme.x --out ./android
# write the app into ./android/app/src/main/assets/www/
scripts/ci_workflow.sh --project ./android
scripts/package_project.sh --project ./android --name x-android-src.zip
```

Then write `android/BUILD.md` containing:

```markdown
# Build the release APK / AAB

1. Install JDK 17+ and the Android SDK (platform 36, build-tools 36.0.0).
2. export ANDROID_HOME=~/Android/Sdk
3. gradle wrapper --gradle-version 8.13    # only if gradle/wrapper/gradle-wrapper.jar is absent
4. ./gradlew --no-daemon clean assembleRelease bundleRelease
5. Artifacts: app/build/outputs/apk/release/app-release.apk
              app/build/outputs/bundle/release/app-release.aab

## Signing (required for a publishable build)
keytool -genkeypair -v -keystore release.keystore -alias release \
  -keyalg RSA -keysize 2048 -validity 10950 -dname "CN=Your Name"
printf 'storeFile=%s/release.keystore\nstorePassword=PASS\nkeyAlias=release\nkeyPassword=PASS\n' "$PWD" > keystore.properties

## Or let GitHub build it
Push this folder to GitHub: .github/workflows/android-release.yml builds and
uploads both artifacts. Set the four RELEASE_* secrets first.
```

Hand the user `x-android-src.zip` and state plainly: the source and CI config are
complete, the compile step needs a machine with the Android SDK, and these are
the exact commands.
