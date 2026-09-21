"""Exercise public-key verification without network access or private keys."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_validation", ROOT / "Scripts/validate-release.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class SignedFeedTests(unittest.TestCase):
    def test_published_bootstrap_feed_verifies(self):
        validation.verify_feed(ROOT / "Updates/appcast.xml")

    def test_modified_feed_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "appcast.xml"
            feed = (ROOT / "Updates/appcast.xml").read_bytes()
            path.write_bytes(feed.replace(b"Open Doc", b"Fake Doc", 1))
            with self.assertRaises(subprocess.CalledProcessError):
                validation.verify_feed(path)

    def test_unsigned_feed_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "appcast.xml"
            path.write_text("<rss><channel/></rss>")
            with self.assertRaises(ValueError):
                validation.verify_feed(path)


if __name__ == "__main__":
    unittest.main()
