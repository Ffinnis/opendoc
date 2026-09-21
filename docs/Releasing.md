# Publish an Open Doc release

Releases are built and signed on the release Mac, uploaded to Apple for notarization, then published on GitHub. GitHub Actions validates the download before updating the Sparkle feed.

Users receive updates from [GitHub Releases](https://github.com/Ffinnis/opendoc/releases) through `https://ffinnis.github.io/opendoc/appcast.xml`. Installed apps check daily. Development builds outside Applications and isolated test sessions do not start the updater.

## Set up the release Mac

Complete [Signing](Signing.md) and sign into `gh` with an account that can publish to `Ffinnis/opendoc`.

The Mac also needs the existing Sparkle signing key in its login Keychain under account `roman.potapov.opendoc`. Do not generate a new key for each release. Back it up securely before replacing the release Mac; never commit or upload the private key. GitHub Actions does not need Apple credentials or this key.

Download the pinned Sparkle tools:

```sh
xcodebuild -resolvePackageDependencies -project opendoc.xcodeproj -scheme opendoc \
  -clonedSourcePackagesDirPath build/SourcePackages
```

## Prepare a version

1. Update `MARKETING_VERSION` and increase `CURRENT_PROJECT_VERSION` in all project configurations.
2. Update [CHANGELOG.md](../CHANGELOG.md), run the checks in [Contributing](../CONTRIBUTING.md#check-your-change), commit, and push.
3. Run the following command with the new version:

```sh
python3 Scripts/release.py prepare 1.2.0
```

The checkout must be clean. The script saves the source commit and build number, builds a universal Mac archive, and submits it to Apple. Keep `build/releases/1.2.0` until publication finishes.

## Publish after notarization

```sh
python3 Scripts/release.py publish 1.2.0
```

If Apple is still processing, keep the archive and retry this command later. Do not run `prepare` again to check status. If Apple rejects the app, resolve the rejection before publishing.

Once notarization passes, the script verifies the app, signs the ZIP and update feed, uploads them to a draft, and publishes the release. The tag points to the source commit recorded during preparation.

Check the release notes for clear descriptions of user-visible changes. Then check the **Deploy updates** workflow. A release page alone does not confirm that automatic updates are available. The workflow must validate the files and finish deploying the feed. Prereleases stay out of the stable feed.

## Recover an interrupted publication

If a draft for that version already exists, inspect it before continuing. The script does not resume an existing draft automatically. Confirm its source commit, upload the verified ZIP and signed `appcast.xml` if missing, and validate the local assets before publishing the draft:

```sh
python3 Scripts/validate-release.py build/releases/1.2.0/assets v1.2.0
```

Do not publish an empty draft or an app still waiting for notarization. Do not overwrite a published version. Corrections need a new release with a higher build number.

## First release and forks

Set GitHub Pages to use **GitHub Actions**. Before the first stable release, run **Deploy updates** manually. It publishes a signed empty feed, so update checks work but offer no download yet.

Forks need their own repository URLs, update feed, and Sparkle signing key. Update the scripts, workflow, and app configuration before publishing. Keep the bundled [Sparkle license](../opendoc/Sparkle-LICENSE.txt) in distributions.

To verify the initial feed without private keys:

```sh
python3 Scripts/validate-release.py --feed Updates/appcast.xml
```

Regenerate signed feeds with Sparkle's tools. Editing the XML by hand invalidates its signature.
