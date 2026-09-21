# Sign a Mac build

You do not need an Apple signing account for the local build described in [Contributing](../CONTRIBUTING.md#build-from-source). Signing is needed for distribution.

## Set up Xcode

Add your Apple Account in Xcode Settings. Create `Configuration/LocalSigning.xcconfig` with your team ID:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

This file is ignored by Git. Keep account details and signing keys out of the repository. Choose the **opendoc** scheme and **My Mac**. The project targets macOS only.

Xcode uses automatic Apple Development signing for local builds. A Mac distribution needs an Apple Developer Program membership and a Developer ID Application certificate. Xcode can use a cloud-managed certificate through the signed-in account.

## Distribute the app

For an Open Doc release, follow [Releasing](Releasing.md). Its script builds both Mac architectures and submits the archive to Apple.

You can also archive through Xcode and choose **Developer ID**, automatic signing, and notarization in Organizer.

An upload success means Apple received the app. Wait for notarization to finish before distributing it. Keep the archive while it is processing; uploading another copy will not check the first submission's status.

After export, verify the app. Replace the example path with your exported bundle:

```sh
codesign --verify --deep --strict /path/to/opendoc.app
xcrun stapler validate /path/to/opendoc.app
spctl --assess --type execute --verbose=2 /path/to/opendoc.app
```

Keep the archive and its debug symbols for each release. Never commit private keys, account credentials, provisioning profiles, or app bundles.

Apple's guides cover [Developer ID](https://developer.apple.com/developer-id/) and the [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
