"""Release queue regressions. No network, signing keys, or real archives."""
from contextlib import ExitStack
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import release


class ReleaseQueueTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.stack.enter_context(patch.object(release, "ROOT", self.root))
        self.version = "1.2.0"
        self.manifest = {"version": self.version, "build": "20", "commit": "a" * 40}
        self.directory = self.root / "build/releases" / self.version
        self.directory.mkdir(parents=True)
        (self.directory / "release.json").write_text(json.dumps(self.manifest))
        self.existing = {"tag_name": "v1.2.0", "target_commitish": "a" * 40,
                         "draft": True, "prerelease": False, "assets": []}

    def state(self):
        return json.loads((self.directory / "queue.json").read_text())

    def queued(self):
        release.queue_state(self.directory, self.manifest, "queued", "Waiting")

    def test_enqueue_adopts_archive_and_resumes_draft_without_resubmission(self):
        with patch.object(release, "prepare") as prepare, patch.object(release, "run", return_value="") as run, \
                patch.object(release, "releases", return_value=[self.existing]):
            release.enqueue(self.version, self.directory)
        prepare.assert_not_called()
        self.assertEqual([c.args[0] for c in run.call_args_list], ["git"])
        self.assertEqual(self.state()["status"], "queued")

    def test_new_draft_uses_curated_notes_and_archived_commit(self):
        notes = self.directory / "notes.md"
        notes.write_text("Fixes app menus.")
        with patch.object(release, "run") as run:
            release.ensure_draft(self.version, self.directory, self.manifest, None)
        self.assertIn(notes, run.call_args.args)
        self.assertIn(self.manifest["commit"], run.call_args.args)
        self.assertIn("--draft", run.call_args.args)

    def test_source_mismatch_or_wrong_tag_blocks_release(self):
        wrong_source = {**self.existing, "target_commitish": "b" * 40}
        with self.assertRaises(ValueError):
            release.release_for(self.version, self.manifest, [wrong_source])
        with patch.object(release, "run", return_value="b" * 40 + "\trefs/tags/v1.2.0\n"):
            with self.assertRaises(ValueError):
                release.release_for(self.version, self.manifest, [self.existing])

    def test_annotated_tag_checks_peeled_commit(self):
        refs = "b" * 40 + "\trefs/tags/v1.2.0\n" + "a" * 40 + "\trefs/tags/v1.2.0^{}\n"
        with patch.object(release, "run", return_value=refs):
            self.assertEqual(release.release_for(self.version, self.manifest, [self.existing]), self.existing)

    def test_pending_notarization_is_retryable_but_rejection_is_failure(self):
        for output, expected in [("Archive is processing and not ready for distribution", release.Pending),
                                 ("Archive was rejected", RuntimeError), ("Authentication failed", RuntimeError)]:
            with self.subTest(output=output), patch.object(release.subprocess, "run", return_value=
                    subprocess.CompletedProcess([], 1, stdout=output)):
                with self.assertRaises(expected):
                    release.export_notarized(self.directory)

    def test_ci_gates_exact_archived_commit(self):
        for checks, expected in [([], release.Pending), ([{"status": "in_progress"}], release.Pending),
                                ([{"status": "completed", "conclusion": "failure"}], ValueError)]:
            with self.subTest(checks=checks), patch.object(release, "run", return_value=json.dumps(checks)) as run:
                with self.assertRaises(expected):
                    release.check_ci(self.manifest)
                self.assertIn(self.manifest["commit"], run.call_args.args)
        with patch.object(release, "run", return_value='[{"status":"completed","conclusion":"success"}]'):
            release.check_ci(self.manifest)

    def test_unqueued_archives_are_not_published(self):
        with patch.object(release, "publish") as publish:
            self.assertEqual(release.drain(), 0)
        publish.assert_not_called()

    def test_pending_queue_stays_queued_then_publishes_once(self):
        self.queued()
        with patch.object(release, "publish", side_effect=release.Pending("Waiting for Apple")):
            self.assertEqual(release.drain(), 0)
        self.assertEqual(self.state()["status"], "queued")
        with patch.object(release, "publish", return_value="Published") as publish:
            self.assertEqual(release.drain(), 0)
            self.assertEqual(release.drain(), 0)
            publish.assert_called_once()
        self.assertEqual(self.state()["status"], "published")

    def test_failure_stops_retries_until_explicitly_requeued(self):
        self.queued()
        with patch.object(release, "publish", side_effect=RuntimeError("Bad signature")) as publish:
            self.assertEqual(release.drain(), 1)
            self.assertEqual(release.drain(), 0)
            publish.assert_called_once()
        self.assertEqual(self.state()["status"], "failed")

    def test_changed_manifest_blocks_publication(self):
        self.queued()
        (self.directory / "release.json").write_text(json.dumps({**self.manifest, "build": "21"}))
        with patch.object(release, "publish") as publish:
            self.assertEqual(release.drain(), 1)
        publish.assert_not_called()
        self.assertEqual(self.state()["build"], "20")

    def test_newer_stable_release_blocks_old_queue_but_draft_does_not(self):
        newer = {**self.existing, "tag_name": "v1.10.0"}
        release.check_release_order(self.version, [newer])
        with self.assertRaises(ValueError):
            release.check_release_order(self.version, [{**newer, "draft": False}])

    def test_published_release_is_never_overwritten(self):
        published = {**self.existing, "draft": False,
                     "assets": [{"name": "OpenDoc-1.2.0.zip"}, {"name": "appcast.xml"}]}
        with patch.object(release, "releases", return_value=[published]), \
                patch.object(release, "run", return_value="") as run, patch.object(release, "export_notarized") as export:
            self.assertIn("Already published", release.publish(self.version, self.directory))
        export.assert_not_called()
        self.assertEqual([c.args[0] for c in run.call_args_list], ["git"])

    def test_resume_uploads_only_after_all_signature_checks(self):
        info = self.directory / "notarized/opendoc.app/Contents/Info.plist"
        info.parent.mkdir(parents=True)
        info.write_bytes(plistlib.dumps({"SUPublicEDKey": "public", "CFBundleVersion": "20",
                                          "CFBundleShortVersionString": self.version}))
        with patch.object(release, "releases", return_value=[self.existing]), \
                patch.object(release, "run", side_effect=lambda *a, **k: "public" if a[0] == release.TOOLS / "generate_keys" else "") as run, \
                patch.object(release, "check_ci"), patch.object(release, "export_notarized"):
            release.publish(self.version, self.directory)
        calls = [c.args for c in run.call_args_list]
        upload = next(i for i, c in enumerate(calls) if c[:3] == ("gh", "release", "upload"))
        for check in ["codesign", "xcrun", "spctl", "python3", release.TOOLS / "sign_update"]:
            self.assertTrue(any(c[0] == check for c in calls[:upload]))
        self.assertFalse(any(c[:3] == ("gh", "release", "create") for c in calls))
        self.assertEqual(calls[-1][:3], ("gh", "release", "edit"))

    def test_lock_prevents_overlapping_commands(self):
        with release.queue_lock():
            with self.assertRaises(SystemExit):
                with release.queue_lock():
                    self.fail("Second publisher acquired the lock")
        with release.queue_lock():
            pass

    def test_failed_app_signature_prevents_github_upload(self):
        def command(*args, **kwargs):
            if args[0] == "codesign":
                raise subprocess.CalledProcessError(1, args)
            return ""
        with patch.object(release, "releases", return_value=[self.existing]), \
                patch.object(release, "run", side_effect=command) as run, \
                patch.object(release, "check_ci"), patch.object(release, "export_notarized"):
            with self.assertRaises(subprocess.CalledProcessError):
                release.publish(self.version, self.directory)
        self.assertFalse(any(c.args[0] == "gh" for c in run.call_args_list))


if __name__ == "__main__":
    unittest.main()
