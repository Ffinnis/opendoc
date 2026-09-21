# Signing and notarization

Open Doc uses automatic Apple Development signing for Xcode builds. Add your Apple Account in Xcode Settings, then create the ignored `Configuration/LocalSigning.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

Select **My Mac** and the **opendoc** scheme. The Mac app does not require a provisioning profile. The project supports macOS only and does not request iOS provisioning.

## Distribute the Mac app

An Apple Developer Program membership is required. Archive both Mac architectures:

```sh
xcodebuild -project opendoc.xcodeproj -scheme opendoc \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/distribution/OpenDoc.xcarchive \
  -allowProvisioningUpdates archive
```

In Xcode Organizer, distribute the archive with **Developer ID**, automatic signing, and notarization. Xcode can use a cloud-managed Developer ID Application certificate through the signed-in account. A local Developer ID private key is not required for this export workflow. The development signing private key stays in Keychain.

For command-line export, create an ignored `build/distribution/ExportOptions.plist` containing:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>YOUR_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict></plist>
```

Submit the archive to Apple's notary service:

```sh
xcodebuild -exportArchive \
  -archivePath build/distribution/OpenDoc.xcarchive \
  -exportOptionsPlist build/distribution/ExportOptions.plist \
  -allowProvisioningUpdates
```

An upload success means Apple received the app; it does not mean notarization passed. When Apple finishes processing, export the notarized app:

```sh
xcodebuild -exportNotarizedApp \
  -archivePath build/distribution/OpenDoc.xcarchive \
  -exportPath build/distribution/notarized

codesign --verify --deep --strict build/distribution/notarized/opendoc.app
xcrun stapler validate build/distribution/notarized/opendoc.app
spctl --assess --type execute --verbose=2 build/distribution/notarized/opendoc.app
```

If export reports that the archive is still processing, retain the archive and check again later. Do not upload another copy just to poll status. For a signed local export without notarization, use `destination = export`; that output is not a notarized release.

Never commit signing private keys, account credentials, provisioning profiles, or app bundles. Retain the archive for each distributed build, including its debug symbols.

Apple documentation: [Developer ID](https://developer.apple.com/developer-id/), [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
