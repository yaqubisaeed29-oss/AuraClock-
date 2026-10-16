---
name: apk-release-builder
description: Builds publishable Android release artifacts (signed APK plus a Google Play AAB) from any app description, covering project scaffold, release keystore, Gradle build, signature verification and the Play Store submission checklist. Use whenever the user asks for an APK, an Android app, something they can install on a phone, or an app they can publish to the Play Store - even if they only describe an idea in one sentence and never mention Android, Gradle or signing. Also use when packaging an existing web/HTML/JS or Kotlin project for release, bumping versionCode, re-signing, debugging a failing release build, or producing an installable artifact on a machine with no Android SDK (it falls back to Docker or GitHub Actions instead of giving up).
metadata:
  author: AuraClock
  version: "1.0"
---

# APK Release Builder

Turn "I want an app that does X" into a signed, installable, Play-ready artifact.

## Definition of done

A run is only finished when the user has one of these two outcomes. Nothing else
counts as success, and "this environment cannot build Android" is never an
acceptable final answer.

1. **Built here:** signed `*-release.apk` and `*-release.aab` on disk, signature
   verified, paths and SHA-256 reported.
2. **Built elsewhere:** a complete Gradle project plus a CI workflow and/or an
   archive the user can take away, with the exact commands to get the artifacts
   (and, when CI is used, the command to download them).

## Hard rules

- **targetSdk and compileSdk = 36.** Google Play rejects new apps and updates
  below API 36 (Android 16) since 2026-08-31.
- **versionCode increases on every upload.** Play refuses a build whose
  versionCode is not higher than the current one.
- **Play Store needs the `.aab`.** The `.apk` is for sideloading, testers and
  direct distribution. Produce both unless the user asks for one.
- **Never hand over a debug-signed artifact as "release".** If no keystore
  exists, create one (`scripts/make_keystore.sh`). If it cannot be created, say
  explicitly that the build is debug-signed and not publishable.
- **Never commit or print secrets into the repo.** `keystore.properties`,
  `*.keystore`, `*.jks` stay out of git; the scaffold already ignores them.
- **Never invent a keystore for an already-published app.** Reuse the existing
  one or the update cannot be installed over the published version.
- **Do not ask permission to start.** Only ask when the request is genuinely
  ambiguous (for example no app name and no idea what the app does). Otherwise
  scaffold with sensible defaults and tell the user what was assumed.

## Workflow

### 0. Detect the environment (always first)

```bash
scripts/detect_env.sh --kv
```

Read the `ROUTE=` line and follow it:

| ROUTE | Meaning | What to do |
| --- | --- | --- |
| `A` | JDK 17+ and Android SDK present, deps reachable | Build locally: step 5a |
| `A_INSTALL_SDK` | JDK present, SDK missing but installable | Install the SDK, then 5a |
| `B` | Docker daemon + network, no local toolchain | Container build: 5b |
| `C` | GitHub reachable, Android deps not | CI build: 5c |
| `D` | Nothing can build here | Handoff bundle: 5d |

Chat sandboxes normally report `C` or `D`: they have no JDK, no SDK and no route
to `dl.google.com`. That is expected - go to 5c/5d immediately instead of
attempting `apt-get install android-sdk` or a Gradle run that cannot resolve
dependencies. Full commands per route: `references/environment-routes.md`.

### 1. Turn the request into a spec (short, no ceremony)

Decide and write down in one block: app name, package id (reverse DNS, for
example `com.<owner>.<app>`), the screens/features, offline vs online, accent and
background colour, `versionCode` (1 for a first build) and `versionName` (`1.0`).
Do not interrogate the user - pick defaults, state them, keep moving.

### 2. Scaffold the project

```bash
scripts/scaffold.sh --app-name "Aura Clock" --package com.acme.auraclock \
  --out ./android --version-code 1 --version-name 1.0 --accent "#4CC9F0"
```

Produces a framework-only WebView host: no AndroidX, no Kotlin plugin, nothing
to download beyond AGP itself. That is deliberate - it is the configuration
least likely to fail. `references/app-templates.md` explains when to switch to
native Kotlin/Compose, Capacitor, Flutter or React Native instead, and holds the
AGP/Gradle/JDK compatibility matrix.

### 3. Write the actual app

The product lives in `app/src/main/assets/www/` (`index.html` is the entry
point, referenced by `MainActivity.START_URL`).

Rules for the code you write there:

- **No CDNs, no remote fonts, no `http://` assets.** A bundled app must work in
  airplane mode; every dependency goes into the `www/` folder.
- Persist with `localStorage`/IndexedDB; there is no backend unless the user
  asked for one.
- Layout for a phone: `100dvh`, `viewport-fit=cover`, `env(safe-area-inset-*)`,
  touch targets >= 44px, no hover-only interaction.
- Native calls go through `window.AndroidBridge`: `getAppVersion()`,
  `getVersionCode()`, `getPackageName()`, `vibrate(ms)`, `share(subject,text)`,
  `openExternal(url)`. Guard with `if (window.AndroidBridge)` so the page also
  works in a desktop browser.
- Edge-to-edge is enforced on Android 15/16: the host already pads the WebView
  by the system bar insets, so do not add a second top padding in CSS.
- Test it in a browser first (open `index.html`), then package. Fixing a blank
  screen after the build is much more expensive.

### 4. Signing key

```bash
scripts/make_keystore.sh --project ./android --cn "Your Name" --org "Your Org"
```

Creates `release.keystore` + `keystore.properties` (both git-ignored) and prints
the passwords once. Tell the user in plain words: **back up the keystore and the
two passwords outside the repo**; losing them means the published app can never
be updated again. Skip this step only if the user explicitly wants an
unpublishable test build, and say so out loud.

### 5. Build

**5a. Local (ROUTE A / A_INSTALL_SDK)**

```bash
scripts/build_release.sh --project ./android      # APK + AAB into ./android/dist/
```

**5b. Docker (ROUTE B)** - use `assets/docker/Dockerfile.android`; exact
commands in `references/environment-routes.md`.

**5c. CI (ROUTE C)**

```bash
scripts/ci_workflow.sh --project ./android        # writes .github/workflows/
scripts/package_project.sh --project ./android    # zips the project for handoff
```

Then give the user the push commands, the four `gh secret set` lines for
signing, and how to fetch the result:
`gh run download --name android-release`.

**5d. Handoff (ROUTE D)** - `package_project.sh`, plus a written `BUILD.md`
inside the archive with the commands from route A, and an honest one-line
explanation of why the build could not happen here.

### 6. Verify before declaring success

```bash
scripts/verify_release.sh --project ./android
```

Must print `RESULT: PASS`. Check that the report shows a real certificate (not
`CN=Android Debug`), `targetSdkVersion: 36`, and a `launchable-activity`. If
apksigner is unavailable in this environment, say which checks were skipped
instead of implying they passed.

### 7. Hand over

Report: file paths, sizes, SHA-256, what was assumed (name, package id,
versions), and the two next actions -

- install on a device: `adb install -r dist/<app>-release.apk` (or enable
  "install unknown apps" and open the APK),
- publish: Play Console -> Production -> Create new release -> upload the
  `.aab`. Full checklist, including the closed-testing rule for new personal
  accounts, in `references/play-store-checklist.md`.

## Communication

Mirror the user's language (if they write Persian, answer in Persian) while
keeping code, file paths, log output and Gradle/Play terminology in English.
Never paste a full Gradle stack trace into chat - quote the failing line and the
fix. When something could not be done here, lead with what the user *does* have
and the single command that finishes the job.

## Contents of this skill

| Path | Use |
| --- | --- |
| `scripts/detect_env.sh` | Environment probe + route decision |
| `scripts/scaffold.sh` | Generate the Android project |
| `scripts/make_keystore.sh` | Create/reuse the release signing key |
| `scripts/build_release.sh` | Build signed APK + AAB into `dist/` |
| `scripts/verify_release.sh` | Signature, badging and alignment checks |
| `scripts/ci_workflow.sh` | GitHub Actions build (route C) |
| `scripts/package_project.sh` | Zip the project for handoff (route C/D) |
| `assets/templates/webview/` | The project template |
| `assets/ci/android-release.yml` | CI workflow template |
| `assets/docker/Dockerfile.android` | Container build image (route B) |
| `references/environment-routes.md` | Exact commands for routes A, A2, B, C, D |
| `references/app-templates.md` | Version matrix; when to leave the WebView template |
| `references/troubleshooting.md` | Build/install/Play error -> cause -> fix |
| `references/play-store-checklist.md` | Artifact -> published app |
