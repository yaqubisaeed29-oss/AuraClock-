# Troubleshooting

Symptom -> cause -> fix. Read the actual first error line in a Gradle log;
everything after it is usually noise.

## Toolchain and configuration

**`SDK location not found. Define a valid SDK location with an ANDROID_HOME environment variable`**
No `local.properties` and no `ANDROID_HOME`. `build_release.sh` writes
`local.properties` automatically when it can find an SDK; otherwise install one
(route A2) or export `ANDROID_HOME`.

**`Minimum supported Gradle version is X. You are currently using version Y`**
AGP/Gradle mismatch. Bump the wrapper:

```bash
sed -i '' 's/gradle-.*-bin.zip/gradle-8.13-bin.zip/' gradle/wrapper/gradle-wrapper.properties  # macOS
sed -i    's/gradle-.*-bin.zip/gradle-8.13-bin.zip/' gradle/wrapper/gradle-wrapper.properties  # Linux
```

Known-good pairs: AGP 8.13.0 + Gradle 8.13 (default), AGP 9.4.0 + Gradle 9.6.0,
AGP 8.7.3 + Gradle 8.9. Full matrix in `app-templates.md`.

**`Android Gradle plugin requires Java 17 or newer`**
Install Temurin 17/21, or pin the JDK for the build in `gradle.properties`:
`org.gradle.java.home=/path/to/jdk17`.

**`Could not find or load main class org.gradle.wrapper.GradleWrapperMain`**
`gradle/wrapper/gradle-wrapper.jar` is missing. Run
`gradle wrapper --gradle-version 8.13 --distribution-type bin` with any local
Gradle, or use route B/C where the wrapper is bootstrapped for you.

**`Could not resolve com.android.application:com.android.application.gradle.plugin`**
No network to `dl.google.com` / `repo.maven.apache.org`, or a proxy. This is
normal inside a chat sandbox - switch to route C (CI) rather than retrying.

**`Failed to install the following SDK components: platforms;android-36` / `licenses not accepted`**
```bash
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platforms;android-36" "build-tools;36.0.0"
```

**`Duplicate class ... found in modules` / `2 files found with path 'META-INF/...'`**
Conflicting dependencies. The default template has zero dependencies, so this
only appears after adding libraries. Add excludes under
`android.packaging.resources.excludes` (already present) or drop the duplicate
module.

## Build and packaging

**`error: resource mipmap/ic_launcher not found`**
The template ships only `res/mipmap-anydpi-v26/ic_launcher.xml`, which covers
API 26+. If `minSdk` was lowered below 26, add real PNGs
(`mipmap-hdpi/ic_launcher.png` 72px, `mipmap-xhdpi` 96px, `mipmap-xxhdpi`
144px, `mipmap-xxxhdpi` 192px) or raise `minSdk` back to 26.

**Lint `NewApi` fails the release build**
`lint.abortOnError` is already `false` in the template. If it was re-enabled,
guard the call with `if (Build.VERSION.SDK_INT >= X)` or move it into a nested
class annotated `@android.annotation.TargetApi(X)` (the pattern used by
`MainActivity.Insets30` and `MainActivity.Back33`).

**App builds, then crashes at launch with `VerifyError` / `NoClassDefFoundError`**
A newer framework type is referenced from a method that also runs on old
devices. Isolate API 30+/33+ code in a static nested class with `@TargetApi`,
and hold references as `Object` in fields.

**APK is unexpectedly large**
Enable `isMinifyEnabled = true` and `isShrinkResources = true` in
`app/build.gradle.kts` (the ProGuard rules for the JS bridge are already in
`proguard-rules.pro`), and prefer the AAB for Play - it delivers only the
splits each device needs.

## Signing and installation

**`apksigner verify` prints `CN=Android Debug`**
The build fell back to the debug key because `keystore.properties` (or the four
`RELEASE_*` env vars) was missing. Run `scripts/make_keystore.sh --project .`
and rebuild. A debug-signed artifact installs on a device but can never be
published or updated by a later properly signed build.

**`INSTALL_FAILED_UPDATE_INCOMPATIBLE` / "App not installed" over an existing app**
The installed app was signed with a different key. Either uninstall the old one
(`adb uninstall <packageId>`) or sign with the original keystore. Published apps
have no uninstall option for existing users - this is why the original keystore
must be backed up.

**`INSTALL_PARSE_FAILED_NO_CERTIFICATES` / install blocked on Android 11+**
The APK only carries a v1 (JAR) signature. Apps targeting API 30+ must be signed
with APK Signature Scheme v2 or newer, which `apksigner` (and Gradle's release
signing) does by default. Never re-sign by hand with `jarsigner` alone.

**Re-signing an already built unsigned APK**
```bash
BT=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)
"$BT/zipalign" -f 4 app-unsigned.apk app-aligned.apk
"$BT/apksigner" sign --ks release.keystore --ks-key-alias release \
  --out app-release.apk app-aligned.apk
"$BT/apksigner" verify --verbose --print-certs app-release.apk
```
Align **before** signing; signing invalidates alignment done afterwards.

**Keystore or password lost**
If Play App Signing was enabled, request an upload-key reset in Play Console
(**Setup > App integrity**) and generate a new upload keystore. Without Play App
Signing, the published app cannot be updated - only a new listing under a new
package id is possible. Enable Play App Signing on day one.

## Runtime (WebView)

**Blank / white screen after install**
Wrong asset path (`file:///android_asset/www/index.html`, singular `asset`,
lowercase, case-sensitive), a JavaScript error, or a CDN dependency blocked
offline. Open `index.html` in a desktop browser first; then check
`chrome://inspect` with a USB-connected device for the WebView console.

**`net::ERR_CLEARTEXT_NOT_PERMITTED`**
The app loads `http://` (not https) content. Serve over https, or add
`android:usesCleartextTraffic="true"` on `<application>` - and prefer a
`res/xml/network_security_config.xml` that allows only the specific domain.

**Back button exits instead of going back inside the app**
On API 33+ `onBackPressed()` is not called; the template registers an
`OnBackInvokedCallback` and requires
`android:enableOnBackInvokedCallback="true"` in the manifest. If that attribute
was removed, back navigation reverts to "finish immediately".

**Content hides under the status bar / gesture area**
Android 15+ is edge to edge and the opt-out attribute no longer works. The host
pads the WebView with system bar insets; in CSS use `env(safe-area-inset-*)`
with `viewport-fit=cover` rather than fixed pixel padding.

## Google Play rejections

| Console message | Fix |
| --- | --- |
| "The target API level must be 36 or higher" | Raise `targetSdk`/`compileSdk` to 36 and rebuild |
| "You must upload an Android App Bundle" | Upload the `.aab`, not the `.apk` (new apps since Aug 2021) |
| "versionCode must be higher than the previous one" | Bump `versionCode` in `app/build.gradle.kts` |
| "APK is signed with a debug certificate" | Sign with the release keystore |
| "Native libraries must be 16 KB page size aligned" | Only for NDK code: use NDK r28+ and AGP 8.5.1+, or ship no native libs |
| "Missing privacy policy" | Add a policy URL in the store listing (required when personal data or sensitive permissions are involved) |
| "You must complete closed testing before production" | Personal accounts created after 2023-11-13: 12 testers opted in for 14 continuous days |

Anything not listed here: read `references/play-store-checklist.md`, then the
exact Play Console message - they name the offending field.
