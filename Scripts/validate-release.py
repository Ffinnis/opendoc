#!/usr/bin/env python3
"""Validate a release before deploying its update feed. No signing secrets needed."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def verify_feed(path):
    feed = path.read_bytes()
    signature = re.search(rb"<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n?\Z", feed)
    if len(feed) > 1_000_000 or signature is None or int(signature[2]) != signature.start():
        raise ValueError("Missing or invalid signed feed footer")
    expected = plistlib.loads((ROOT / "Configuration/MacInfo.plist").read_bytes())
    with tempfile.TemporaryDirectory(prefix="opendoc-feed-") as temp:
        payload = Path(temp) / "feed-payload"
        payload.write_bytes(feed[:signature.start()])
        subprocess.run(["swift", str(ROOT / "Scripts/verify-update.swift"), str(payload),
                        expected["SUPublicEDKey"], signature[1].decode("ascii")], check=True)
    return feed


def validate(directory, tag):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Expected a stable version tag")
    feed = verify_feed(directory / "appcast.xml")
    if len(feed) > 1_000_000 or b"<!DOCTYPE" in feed or b"<!ENTITY" in feed:
        raise ValueError("Invalid feed")
    items = ET.fromstring(feed).findall("channel/item")
    if len(items) != 1:
        raise ValueError("Expected exactly one release in this feed")
    item = items[0]
    enclosure = item.find("enclosure")
    filename = f"OpenDoc-{tag[1:]}.zip"
    archive = directory / filename
    expected_url = f"https://github.com/Ffinnis/opendoc/releases/download/{tag}/{filename}"
    if enclosure is None or enclosure.get("url") != expected_url:
        raise ValueError("Unexpected update download URL")
    if int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("Update length does not match")
    expected = plistlib.loads((ROOT / "Configuration/MacInfo.plist").read_bytes())
    subprocess.run(["swift", str(ROOT / "Scripts/verify-update.swift"), str(archive),
                    expected["SUPublicEDKey"], enclosure.attrib[SPARKLE + "edSignature"]], check=True)
    # Extract only after verifying the archive against the public update key.
    with tempfile.TemporaryDirectory(prefix="opendoc-release-") as temp:
        subprocess.run(["ditto", "-x", "-k", str(archive), temp], check=True)
        app = Path(temp) / "opendoc.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        version = item.findtext(SPARKLE + "version") or enclosure.get(SPARKLE + "version")
        if info["CFBundleIdentifier"] != "roman.potapov.opendoc" or info["CFBundleShortVersionString"] != tag[1:]:
            raise ValueError("App identity does not match the release")
        if info["CFBundleVersion"] != version:
            raise ValueError("Feed build number does not match the app")
        for field in ["SUFeedURL", "SUPublicEDKey", "SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"]:
            if info[field] != expected[field]:
                raise ValueError(f"App has an unexpected {field}")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
        subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
    print(f"Validated {tag}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: validate-release.py assets-directory v1.1.0")
    if sys.argv[1] == "--feed":
        verify_feed(Path(sys.argv[2]).resolve())
    else:
        validate(Path(sys.argv[1]).resolve(), sys.argv[2])
