# Play Store checklist: artifact -> published app

## 0. Before you start

| Item | Requirement |
| --- | --- |
| Artifact format | `.aab` (Android App Bundle). APKs are accepted only for apps published before Aug 2021 |
| targetSdk / compileSdk | 36 (Android 16) for new apps and updates, since 2026-08-31 |
| Signing | Release keystore, APK Signature Scheme v2+. Never the debug key |
| versionCode | Higher than any previously uploaded build |
| Account | Google Play Console, one-time USD 25, identity verification |
| 64-bit | Required for apps with native code (a WebView/Java/Kotlin app is fine) |
| 16 KB page size | Required from 2025-11-01 for apps with native libraries targeting Android 15+ (NDK r28+, AGP 8.5.1+). No native libs -> nothing to do |

## 1. Store listing assets

| Asset | Spec |
| --- | --- |
| App name | max 30 characters |
| Short description | max 80 characters |
| Full description | max 4000 characters |
| App icon | 512 x 512 PNG, 32-bit with alpha (uploaded separately from the APK icon) |
| Feature graphic | 1024 x 500 PNG/JPG |
| Phone screenshots | 2-8, min 320px, max 3840px on the longest side |
| 7-inch / 10-inch tablet screenshots | Optional but recommended |
| Promo video | Optional YouTube URL |

## 2. Console questionnaires (all mandatory)

1. **Privacy policy URL** - required if the app handles personal or sensitive
   data, or requests sensitive permissions. A public page is enough; it must be
   reachable and mention what is collected.
2. **App access** - if any feature is behind a login, provide test credentials.
3. **Ads** - declare whether the app contains advertising.
4. **Content rating** - IARC questionnaire; the result is shown per region.
5. **Target audience and content** - age groups; declaring children changes what
   you may collect and which ads you may show.
6. **Data safety** - every data type collected/shared, whether it is encrypted in
   transit and whether users can request deletion. This must match the actual
   permissions in the manifest; inconsistencies cause rejection.
7. **Declarations** - sensitive permissions (location, SMS, accessibility,
   `QUERY_ALL_PACKAGES`), health/financial features, government affiliation.

## 3. Closed testing (personal accounts only)

Personal Play Console accounts created **after 13 November 2023** must complete a
qualifying closed test before applying for production access:

- at least **12 testers** opted in to the closed testing track,
- continuously for the **14 days** immediately before you apply,
- real people on real devices with distinct Google accounts (emulators and
  duplicate accounts do not count),
- testers must actually **use** the app - since 2026 Google also reviews
  engagement and can reject a test where installers never opened the app,
- upload an `.aab` to the closed testing track first; the 14 days start once that
  release is approved and 12 testers have opted in,
- a tester who drops out and returns restarts their own streak.

Organization accounts, and personal accounts created before that date, are not
subject to this gate. After it is met, apply for production access from the Play
Console Dashboard (review is typically about a week).

## 4. Release

1. Play Console -> **Testing > Closed testing** -> Create new release -> upload
   the `.aab` -> review -> roll out. Wait for approval and run the 14 days if
   the account needs it.
2. **Production -> Create new release -> Upload app bundle**, add release notes
   (max 500 characters, per language), review, then **Start rollout**.
3. Choose **staged rollout** (for example 10% -> 50% -> 100%) so a crash can be
   halted before it reaches everyone.
4. Review time: usually hours to a few days; new developer accounts can take
   longer. Status appears under **Publishing overview**.

## 5. Play App Signing (enable it)

**Setup -> App integrity -> Play App Signing.** Google holds the signing key and
re-signs the app keys derived from your bundle, which means:

- if you lose your **upload key**, you can request a reset instead of losing the
  app forever,
- Play can generate optimised split APKs per device.

You keep an **upload key** (`release.keystore` from this skill) and sign every
bundle with it; Google signs what users install. Record both the upload key and
its passwords in a password manager, and store an offline copy of the `.keystore`
file.

## 6. Distribution outside Google Play

A signed release `.apk` can be distributed directly (website, GitHub Release,
enterprise MDM, `adb install -r`). Users must enable "Install unknown apps" for
the source, and Play Protect may warn on apps it does not recognise - that is
expected for self-distributed builds and does not mean the APK is broken. Keep
`versionCode` increasing there too, or updates will fail to install over the
existing app.

## 7. After publishing

- **Android vitals** (crash rate, ANR rate) - a bad rate reduces visibility in
  search and can trigger warnings.
- Every update needs a higher `versionCode` and must keep targetSdk within one
  year of the latest Android release (next floor: API 36 from 2026-08-31, the
  following year moves again).
- Policy status page in the console lists anything outstanding; fix it before it
  becomes a removal.

## One-line summary for the user

`dist/<app>-<version>-release.aab` -> Play Console -> Production -> Create new
release -> upload -> staged rollout; and back up `release.keystore` + both
passwords outside the repository, because losing them ends the app's update
ability permanently.
