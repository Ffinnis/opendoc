# Releases and automatic updates

Open Doc uses Sparkle 2.10, pinned through Swift Package Manager. Installed copies check the signed feed at `https://ffinnis.github.io/opendoc/appcast.xml` daily. Updates download from GitHub Releases. Both the feed and archives have Ed25519 signatures; the app also uses Developer ID signing and notarization. Users can disable automatic checks in the menu. The updater does not start for CLI workers, isolated tests, or development builds outside Applications.

## Signing on the release Mac

Sign into the Apple Developer account in Xcode and set `Configuration/LocalSigning.xcconfig` as described in [Signing](Signing.md). The release Mac also needs `gh auth login` with access to `Ffinnis/opendoc`.

Resolve Sparkle tools:

```sh
xcodebuild -resolvePackageDependencies -project opendoc.xcodeproj -scheme opendoc \
  -clonedSourcePackagesDirPath build/SourcePackages
```

The Sparkle private key is stored in this Mac's login Keychain under account `roman.potapov.opendoc`. `SUPublicEDKey` in `Configuration/MacInfo.plist` contains only the public key. Do not regenerate the key for each release. Back up the private key securely before replacing this Mac. Never commit or attach private signing keys to a release.

Xcode uses its signed-in account and cloud-managed Developer ID certificate. GitHub Actions does not need Apple credentials or the Sparkle private key. Building and signing happen on the release Mac; validating and deploying the update feed happen automatically on GitHub after publication.

## Publish a version

1. Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in Xcode for all configurations. The build number must increase for every update, even if the marketing version stays the same.
2. Run the Mac tests, commit the changes, and push `main`. Prepare requires a clean checkout and records that source commit with the archive.
3. Build the universal Mac archive and submit it for notarization:

```sh
python3 Scripts/release.py prepare 1.2.0
```

4. Once Apple finishes processing, export, verify, sign the update archive, and publish:

```sh
python3 Scripts/release.py publish 1.2.0
```

`publish` fails while notarization is pending or rejected. Keep the archive and retry after Apple completes processing; do not submit another copy just to poll. The script verifies notarization before creating a release, uploads the ZIP and signed appcast to a draft, then publishes it. The tag points to the commit recorded during preparation.

The **Deploy updates** workflow downloads the latest stable release, verifies the signed feed and archive against the public key, validates the app identity and build number, and checks code signing and notarization. Only then does it deploy `appcast.xml` to GitHub Pages. Prereleases do not enter the stable feed. A failed validation leaves the previous feed deployed.

If publication stops after creating a draft, inspect its assets before publishing that existing draft in GitHub. Do not recreate or overwrite a published version. Use a higher build number for corrections.

## First deployment and forks

GitHub Pages must use **GitHub Actions** as its deployment source. Run **Deploy updates** manually to initialize the feed before the first release. It deploys the signed empty `Updates/appcast.xml` when no stable release exists. Automatic checks then work but offer no download until the first notarized release is published.

Forks must change the repository URLs in the scripts, workflow, and Info.plist and use their own update-signing key. Do not publish updates to the upstream feed. The bundled [Sparkle license](../opendoc/Sparkle-LICENSE.txt) must accompany distributions.

## Checks

```sh
python3 Scripts/validate-release.py --feed Updates/appcast.xml
python3 Scripts/validate-release.py build/releases/1.2.0/assets v1.2.0
```

The first verifies the feed without private keys. The second also validates its downloaded app archive. Avoid editing signed XML by hand; regenerate it using Sparkle's tools.
