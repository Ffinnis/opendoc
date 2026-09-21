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

## Queue a version

1. Update `MARKETING_VERSION` and increase `CURRENT_PROJECT_VERSION` in all project configurations.
2. Update [CHANGELOG.md](../CHANGELOG.md), run the checks in [Contributing](../CONTRIBUTING.md#check-your-change), commit, and push.
3. Run the following command with the new version:

```sh
python3 Scripts/release.py enqueue 1.2.0
```

The checkout must be clean for a new build. The command saves the source commit and build number, builds a universal Mac archive, and submits it to Apple. It creates a GitHub draft and queues publication, then returns without waiting for notarization. Keep `build/releases/1.2.0` until publication finishes.

If this version already has an archive from `prepare`, `enqueue` uses it without rebuilding or resubmitting. Edits made since that archive was created are not part of the release.

For custom release notes, write `build/releases/1.2.0/notes.md` after `prepare` and before `enqueue`, or edit the GitHub draft. Otherwise GitHub generates the notes.

## Background publication

The release Mac runs a single queue check with:

```sh
python3 Scripts/release.py drain
```

Each check waits for successful CI on the archived commit and asks Xcode whether notarization has finished. Pending releases stay queued. Approved builds pass signature and notarization checks before the script creates the ZIP, signs the update feed, uploads both files, and publishes the draft.

A Codex background task on the maintainer's Mac runs this command every 15 minutes. That task is a local setup, not part of the repository. The Mac and Codex must be running, with Xcode signed in, `gh` authenticated, and the signing key available in Keychain. A Keychain permission prompt may need attention. GitHub Actions does not build or sign these releases.

On another release Mac, arrange recurring execution of `drain` with your preferred scheduler. Checks do not sleep or poll in a loop, and a file lock prevents overlapping release commands.

Inspect the queue at any time:

```sh
python3 Scripts/release.py status
```

Check the release notes for clear descriptions of user-visible changes. Then check the **Deploy updates** workflow. A release page alone does not confirm that automatic updates are available. The workflow must validate the files and finish deploying the feed. Prereleases stay out of the stable feed.

## Retry or cancel

CI failures, rejected exports, signature errors, and command timeouts mark the queued version as `failed`. Background checks leave it alone until you resolve the problem and requeue it:

```sh
python3 Scripts/release.py enqueue 1.2.0
```

Publication can resume an existing draft only when its source commit and tag match the archive. A partial asset upload is replaced after local validation. Published assets are never overwritten. Older queued versions stop if a newer stable version is already public.

To remove a version from the queue while retaining its archive and GitHub draft:

```sh
python3 Scripts/release.py cancel 1.2.0
```

Manual `prepare VERSION` and `publish VERSION` commands are still available. `prepare` only builds and submits; `publish` performs one publication attempt. Neither command schedules background checks. Do not repeat `prepare` to check Apple's progress, publish an empty draft, or overwrite a public version. Code changes need a new archive and version.

## First release and forks

Set GitHub Pages to use **GitHub Actions**. In the `github-pages` environment's deployment rules, allow the `main` branch and release tags matching `v*.*.*`. A release workflow runs from its tag, so allowing only `main` blocks publication of the feed even after validation passes.

Before the first stable release, run **Deploy updates** manually. It publishes a signed empty feed, so update checks work but offer no download yet.

Forks need their own repository URLs, update feed, and Sparkle signing key. Update the scripts, workflow, and app configuration before publishing. Keep the bundled [Sparkle license](../opendoc/Sparkle-LICENSE.txt) in distributions.

To verify the initial feed without private keys:

```sh
python3 Scripts/validate-release.py --feed Updates/appcast.xml
```

Regenerate signed feeds with Sparkle's tools. Editing the XML by hand invalidates its signature.
