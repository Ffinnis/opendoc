#!/usr/bin/env python3
"""Sign locally with Xcode, then publish notarized Sparkle updates to GitHub."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPO = "Ffinnis/opendoc"
ACCOUNT = "roman.potapov.opendoc"
TOOLS = ROOT / "build/SourcePackages/artifacts/sparkle/Sparkle/bin"


def run(*args, capture=False):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout


def prepare(version, directory):
    if run("git", "status", "--porcelain", capture=True).strip():
        raise SystemExit("Commit the release source first. The working tree must be clean.")
    if directory.exists():
        raise SystemExit(f"{directory} exists. Use publish to resume a submitted release.")
    commit = run("git", "rev-parse", "HEAD", capture=True).strip()
    directory.mkdir(parents=True)
    archive = directory / "OpenDoc.xcarchive"
    run("xcodebuild", "-project", "opendoc.xcodeproj", "-scheme", "opendoc",
        "-configuration", "Release", "-destination", "generic/platform=macOS",
        "-clonedSourcePackagesDirPath", "build/SourcePackages", "-archivePath", archive,
        "-allowProvisioningUpdates", "archive")
    archive_info = plistlib.loads((archive / "Info.plist").read_bytes())
    properties = archive_info["ApplicationProperties"]
    if properties["CFBundleShortVersionString"] != version:
        raise SystemExit("Set MARKETING_VERSION in Xcode to the requested release version first.")
    team = properties["Team"]
    options = directory / "ExportOptions.plist"
    options.write_bytes(plistlib.dumps({"method": "developer-id", "teamID": team,
                                       "signingStyle": "automatic", "destination": "upload"}))
    (directory / "release.json").write_text(json.dumps({"commit": commit, "version": version,
                                                       "build": properties["CFBundleVersion"]}))
    run("xcodebuild", "-exportArchive", "-archivePath", archive,
        "-exportOptionsPlist", options, "-allowProvisioningUpdates")
    print(f"Submitted to Apple. When processing finishes, run: python3 Scripts/release.py publish {version}")


def publish(version, directory):
    manifest = json.loads((directory / "release.json").read_text())
    if manifest["version"] != version:
        raise SystemExit("Release version does not match its archived source.")
    # This fails while processing or after rejection. Never publish an unnotarized build.
    exported = directory / "notarized"
    run("xcodebuild", "-exportNotarizedApp", "-archivePath", directory / "OpenDoc.xcarchive",
        "-exportPath", exported)
    app = exported / "opendoc.app"
    run("codesign", "--verify", "--deep", "--strict", app)
    run("xcrun", "stapler", "validate", app)
    run("spctl", "--assess", "--type", "execute", app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    public_key = run(TOOLS / "generate_keys", "--account", ACCOUNT, "-p", capture=True).strip()
    if info["SUPublicEDKey"] != public_key or info["CFBundleVersion"] != manifest["build"]:
        raise SystemExit("Signing key or build number does not match the archived app.")
    assets = directory / "assets"
    assets.mkdir(exist_ok=True)
    archive_zip = assets / f"OpenDoc-{version}.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive_zip)
    run(TOOLS / "generate_appcast", "--account", ACCOUNT, "--maximum-deltas", "0",
        "--download-url-prefix", f"https://github.com/{REPO}/releases/download/v{version}/", assets)
    run(TOOLS / "sign_update", "--account", ACCOUNT, "--verify", assets / "appcast.xml")
    run("python3", "Scripts/validate-release.py", assets, f"v{version}")
    # A draft keeps its assets out of the stable feed until upload is complete.
    run("gh", "release", "create", f"v{version}", archive_zip, assets / "appcast.xml",
        "--repo", REPO, "--target", manifest["commit"], "--title", f"Open Doc {version}",
        "--generate-notes", "--draft")
    run("gh", "release", "edit", f"v{version}", "--repo", REPO, "--draft=false", "--latest")
    print("Published. GitHub Actions will validate the release and deploy the update feed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "publish"])
    parser.add_argument("version", help="Marketing version, e.g. 1.1.0. Increment the build number in Xcode too.")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("Version must have three numeric components.")
    directory = ROOT / "build/releases" / args.version
    {"prepare": prepare, "publish": publish}[args.command](args.version, directory)
