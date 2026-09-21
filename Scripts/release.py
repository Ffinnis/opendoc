#!/usr/bin/env python3
"""Queue locally signed Mac releases for publication after CI and notarization."""
import argparse
from contextlib import contextmanager
import fcntl
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPO = "Ffinnis/opendoc"
ACCOUNT = "roman.potapov.opendoc"
TOOLS = ROOT / "build/SourcePackages/artifacts/sparkle/Sparkle/bin"


class Pending(Exception):
    """A release is healthy but not ready to publish yet."""


def manifest_for(version, directory):
    manifest = json.loads((directory / "release.json").read_text())
    if (manifest["version"] != version or not re.fullmatch(r"[0-9a-f]{40}", manifest["commit"])
            or not str(manifest["build"]).isdigit()):
        raise ValueError("Release version, commit, or build does not match its archived source.")
    return manifest


def releases():
    pages = json.loads(run("gh", "api", "--paginate", "--slurp",
                          f"repos/{REPO}/releases?per_page=100", capture=True))
    return [release for page in pages for release in page]


def release_for(version, manifest, all_releases):
    release = next((r for r in all_releases if r["tag_name"] == f"v{version}"), None)
    if release and (release["target_commitish"] != manifest["commit"] or release["prerelease"]):
        raise ValueError("Existing release has a different source commit or is a prerelease.")
    # A pre-existing tag takes precedence over --target when GitHub creates a release.
    refs = run("git", "ls-remote", f"https://github.com/{REPO}.git",
               f"refs/tags/v{version}", f"refs/tags/v{version}^{{}}", capture=True).splitlines()
    if refs and refs[-1].split()[0] != manifest["commit"]:
        raise ValueError("Existing release tag points to a different source commit.")
    return release


def ensure_draft(version, directory, manifest, existing):
    if existing:
        return
    notes = directory / "notes.md"
    note_args = ["--notes-file", notes] if notes.exists() else ["--generate-notes"]
    run("gh", "release", "create", f"v{version}", "--repo", REPO,
        "--target", manifest["commit"], "--title", f"Open Doc {version}",
        *note_args, "--draft")


def queue_state(directory, manifest, status, detail):
    temporary = directory / "queue.json.tmp"
    temporary.write_text(json.dumps({**manifest, "status": status, "detail": detail}, indent=2) + "\n")
    temporary.replace(directory / "queue.json")


@contextmanager
def queue_lock():
    directory = ROOT / "build/releases"
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / ".queue.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("Another release command is running. Nothing changed.")
        yield


def run(*args, capture=False, timeout=300):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True,
                          text=True, timeout=timeout,
                          stdout=subprocess.PIPE if capture else None).stdout


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
        "-allowProvisioningUpdates", "archive", timeout=1800)
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
        "-exportOptionsPlist", options, "-allowProvisioningUpdates", timeout=1800)
    print(f"Submitted to Apple. Queue publication with: python3 Scripts/release.py enqueue {version}")


def enqueue(version, directory):
    if not directory.exists():
        prepare(version, directory)
    manifest = manifest_for(version, directory)
    existing = release_for(version, manifest, releases())
    if existing and not existing["draft"]:
        raise ValueError("This version is already published. Use a new version for changes.")
    ensure_draft(version, directory, manifest, existing)
    queue_state(directory, manifest, "queued", "Waiting for CI and Apple notarization.")
    print(f"Queued {version}. Background drain checks will finish publication.")


def check_ci(manifest):
    checks = json.loads(run("gh", "run", "list", "--repo", REPO, "--workflow", "build.yml",
                            "--commit", manifest["commit"], "--event", "push", "--limit", "1",
                            "--json", "status,conclusion", capture=True))
    if not checks or checks[0]["status"] != "completed":
        raise Pending("Waiting for CI on the archived source commit.")
    if checks[0]["conclusion"] != "success":
        raise ValueError("CI did not pass for the archived source commit. Fix or rerun CI before retrying.")


def export_notarized(directory):
    result = subprocess.run(["xcodebuild", "-exportNotarizedApp", "-archivePath",
                             str(directory / "OpenDoc.xcarchive"), "-exportPath",
                             str(directory / "notarized")], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        if 'is processing and not ready for distribution' in result.stdout:
            raise Pending("Waiting for Apple notarization.")
        raise RuntimeError(f"Notarized export failed:\n{result.stdout[-8000:]}")


def check_release_order(version, all_releases):
    version_tuple = tuple(map(int, version.split(".")))
    for release in all_releases:
        tag = release["tag_name"]
        if (not release["draft"] and not release["prerelease"]
                and re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag)
                and tuple(map(int, tag[1:].split("."))) > version_tuple):
            raise ValueError(f"A newer release, {tag}, is published. Cancel this older queued version.")


def publish(version, directory):
    manifest = manifest_for(version, directory)
    all_releases = releases()
    existing = release_for(version, manifest, all_releases)
    if existing and not existing["draft"]:
        expected = {f"OpenDoc-{version}.zip", "appcast.xml"}
        if not expected.issubset({asset["name"] for asset in existing["assets"]}):
            raise ValueError("Published release is missing assets. Inspect it without overwriting it.")
        return "Already published. No assets changed."
    check_release_order(version, all_releases)
    check_ci(manifest)
    export_notarized(directory)
    exported = directory / "notarized"
    app = exported / "opendoc.app"
    run("codesign", "--verify", "--deep", "--strict", app)
    run("xcrun", "stapler", "validate", app)
    run("spctl", "--assess", "--type", "execute", app)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    public_key = run(TOOLS / "generate_keys", "--account", ACCOUNT, "-p", capture=True).strip()
    if (info["SUPublicEDKey"] != public_key or info["CFBundleVersion"] != manifest["build"]
            or info["CFBundleShortVersionString"] != version):
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
    # Recheck after signing, which may wait for an interactive Keychain prompt.
    all_releases = releases()
    check_release_order(version, all_releases)
    existing = release_for(version, manifest, all_releases)
    if existing and not existing["draft"]:
        raise ValueError("The release was published elsewhere. No assets changed.")
    ensure_draft(version, directory, manifest, existing)
    run("gh", "release", "upload", f"v{version}", archive_zip, assets / "appcast.xml",
        "--repo", REPO, "--clobber")
    run("gh", "release", "edit", f"v{version}", "--repo", REPO, "--draft=false", "--latest")
    return "Published. GitHub Actions will validate the release and deploy the update feed."


def drain():
    failed = False
    for path in sorted((ROOT / "build/releases").glob("*/queue.json"),
                       key=lambda p: tuple(map(int, p.parent.name.split("."))), reverse=True):
        state = json.loads(path.read_text())
        if state["status"] != "queued":
            continue
        directory = path.parent
        try:
            manifest = manifest_for(directory.name, directory)
            if any(state[key] != manifest[key] for key in ("version", "commit", "build")):
                raise ValueError("Queued source identity changed. Inspect the archive before requeuing.")
            detail = publish(directory.name, directory)
            status = "published"
        except Pending as error:
            status, detail = "queued", str(error)
        except (ValueError, KeyError, RuntimeError, OSError, subprocess.SubprocessError) as error:
            status, detail, failed = "failed", str(error), True
        queue_state(directory, state, status, detail)
        print(f"{directory.name}: {status}. {detail}")
    return int(failed)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                     epilog="""Commands:
  enqueue VERSION  Build and submit, or queue an existing archive; create a draft.
  drain            Check queued releases once and publish those ready to ship.
  status           Print queue state as JSON.
  cancel VERSION   Stop background publication; retain archive and draft.
  prepare VERSION  Build and submit only, without adding to the queue.
  publish VERSION  Attempt publication once, without scheduling retries.

Run drain periodically on the release Mac. See docs/Releasing.md.""")
    parser.add_argument("command", choices=["prepare", "publish", "enqueue", "drain", "status", "cancel"])
    parser.add_argument("version", nargs="?", help="Marketing version, e.g. 1.1.0. Increment the build number in Xcode too.")
    args = parser.parse_args()
    needs_version = args.command not in ("drain", "status")
    if needs_version and (not args.version or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version)):
        parser.error("Version must have three numeric components.")
    if not needs_version and args.version:
        parser.error("This command does not take a version.")
    with queue_lock():
        try:
            if args.command == "drain":
                sys.exit(drain())
            elif args.command == "status":
                states = [json.loads(p.read_text()) for p in sorted((ROOT / "build/releases").glob("*/queue.json"))]
                print(json.dumps(states, indent=2))
            else:
                directory = ROOT / "build/releases" / args.version
                if args.command == "cancel":
                    queue_state(directory, manifest_for(args.version, directory), "cancelled", "Cancelled locally. Archive and GitHub draft retained.")
                else:
                    result = {"prepare": prepare, "publish": publish, "enqueue": enqueue}[args.command](args.version, directory)
                    if result:
                        print(result)
        except (Pending, ValueError, KeyError, RuntimeError, OSError, subprocess.SubprocessError) as error:
            sys.exit(str(error))
