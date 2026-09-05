import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "postcard.py"
SPEC = importlib.util.spec_from_file_location("terrarium_postcard", SCRIPT)
postcard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(postcard)


class PostcardPaths(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="terrarium-postcard-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.directory = self.base / "画像 と Pictures" / "Terrarium"

    def reservation(self):
        return postcard.reserve(str(self.directory))

    def cancel(self, item):
        return postcard.cancel(str(self.directory), item["path"], item["token"])

    def test_spaced_localized_directory_contains_only_private_png_reservation(self):
        item = self.reservation()
        path = Path(item["path"])
        self.assertEqual(path.parent, self.directory)
        self.assertTrue(postcard.GENERATED_NAME.fullmatch(path.name))
        self.assertEqual(path.stat().st_size, 0)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(list(self.directory.iterdir()), [path])
        self.assertLessEqual(len(item["token"]), 8192)
        self.assertEqual(self.cancel(item), {"ok":True,"removed":True,"code":"removed"})
        self.assertEqual(self.cancel(item), {"ok":True,"removed":False,"code":"already_removed"})

    def test_two_saves_never_overwrite_an_existing_output(self):
        first = self.reservation()
        Path(first["path"]).write_bytes(b"existing user image")
        second = self.reservation()
        self.assertNotEqual(first["path"], second["path"])
        self.assertEqual(self.cancel(first), {"ok":False,"removed":False,"code":"not_empty"})
        self.assertEqual(Path(first["path"]).read_bytes(), b"existing user image")
        self.cancel(second)

    def test_mkstemp_collision_uses_exclusive_creation(self):
        self.directory.mkdir(parents=True)
        prefix = "terrarium-20260904-123456-" + "a"*16 + "-"
        collision = self.directory / (prefix + "same____.png")
        collision.write_bytes(b"keep this")
        with mock.patch.object(postcard.secrets, "token_hex", return_value="a"*16), \
             mock.patch.object(postcard.time, "strftime", return_value="20260904-123456"), \
             mock.patch.object(postcard.tempfile, "_get_candidate_names", return_value=iter(["same____","next____"])):
            item = self.reservation()
        self.assertEqual(Path(item["path"]).name, prefix + "next____.png")
        self.assertEqual(collision.read_bytes(), b"keep this")
        self.cancel(item)

    def test_cannot_create_directory_is_a_fixed_error(self):
        blocked = self.base / "not a directory"
        blocked.write_text("keep")
        with self.assertRaises(postcard.PostcardError) as error:
            postcard.reserve(str(blocked / "Terrarium"))
        self.assertEqual(error.exception.code, "cannot_create_directory")
        self.assertEqual(blocked.read_text(), "keep")

    def test_reservation_failure_returns_no_raw_exception_or_private_path(self):
        output = io.StringIO()
        with mock.patch.object(postcard.tempfile, "mkstemp", side_effect=PermissionError("private secret path")), contextlib.redirect_stdout(output):
            status = postcard.main(["reserve","--directory",str(self.directory)])
        self.assertEqual(status, 1)
        self.assertEqual(json.loads(output.getvalue())["code"], "cannot_reserve")
        self.assertNotIn("secret", output.getvalue())
        self.assertEqual(len(output.getvalue().splitlines()), 1)

    def test_failure_after_creation_cleans_only_its_own_empty_file(self):
        with mock.patch.object(postcard, "encode_receipt", side_effect=postcard.PostcardError("invalid_directory",2)):
            with self.assertRaises(postcard.PostcardError):
                self.reservation()
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_symlink_replacement_preserves_its_target(self):
        item = self.reservation()
        path = Path(item["path"])
        target = self.base / "valuable.png"
        target.write_bytes(b"valuable")
        path.unlink(); path.symlink_to(target)
        with self.assertRaises(postcard.PostcardError) as error:
            self.cancel(item)
        self.assertEqual(error.exception.code, "reservation_changed")
        self.assertTrue(path.is_symlink())
        self.assertEqual(target.read_bytes(), b"valuable")

    def test_empty_replacement_and_changed_ctime_are_preserved(self):
        item = self.reservation()
        path = Path(item["path"])
        replacement = self.base / "replacement"
        replacement.touch()
        os.replace(replacement, path)
        with self.assertRaises(postcard.PostcardError) as error:
            self.cancel(item)
        self.assertEqual(error.exception.code, "reservation_changed")
        self.assertTrue(path.exists())
        other = self.reservation()
        os.chmod(other["path"], 0o400)
        with self.assertRaises(postcard.PostcardError):
            self.cancel(other)
        self.assertTrue(Path(other["path"]).exists())

    def test_hardlinks_and_arbitrary_paths_are_not_unlinked(self):
        item = self.reservation()
        linked = self.base / "linked"
        os.link(item["path"], linked)
        with self.assertRaises(postcard.PostcardError):
            self.cancel(item)
        with self.assertRaises(postcard.PostcardError):
            postcard.cancel(str(self.directory), str(linked), item["token"])
        self.assertTrue(linked.exists())
        self.assertTrue(Path(item["path"]).exists())

    def test_directory_identity_is_part_of_the_receipt(self):
        item = self.reservation()
        moved = self.directory.with_name("Previous Terrarium")
        self.directory.rename(moved)
        self.directory.mkdir()
        replacement = self.directory / Path(item["path"]).name
        replacement.touch()
        with self.assertRaises(postcard.PostcardError) as error:
            self.cancel(item)
        self.assertEqual(error.exception.code, "reservation_changed")
        self.assertTrue(replacement.exists())
        self.assertTrue((moved / replacement.name).exists())

    def test_cleanup_failure_is_explicit_and_preserves_file(self):
        item = self.reservation()
        with mock.patch.object(postcard.os, "unlink", side_effect=PermissionError("not allowed")):
            with self.assertRaises(postcard.PostcardError) as error:
                self.cancel(item)
        self.assertEqual(error.exception.code, "cleanup_failed")
        self.assertTrue(Path(item["path"]).exists())

    def test_invalid_tokens_are_bounded_and_do_not_touch_files(self):
        item = self.reservation()
        for token in ("", "../receipt", "A"*8193, "e30", "💥"):
            with self.assertRaises(postcard.PostcardError) as error:
                postcard.cancel(str(self.directory),item["path"],token)
            self.assertEqual(error.exception.exit_code, 2)
        self.assertTrue(Path(item["path"]).exists())
        self.cancel(item)

    def test_cli_always_reports_one_structured_response(self):
        reserve = subprocess.run([sys.executable,str(SCRIPT),"reserve","--directory",str(self.directory)],capture_output=True,text=True,check=False)
        self.assertEqual(reserve.returncode, 0)
        self.assertEqual(reserve.stderr, "")
        self.assertEqual(len(reserve.stdout.splitlines()), 1)
        item = json.loads(reserve.stdout)
        cleanup = subprocess.run([sys.executable,str(SCRIPT),"cancel","--directory",str(self.directory),"--path",item["path"],"--token",item["token"]],capture_output=True,text=True,check=False)
        self.assertEqual(cleanup.returncode, 0)
        self.assertTrue(json.loads(cleanup.stdout)["removed"])
        invalid = subprocess.run([sys.executable,str(SCRIPT),"reserve"],capture_output=True,text=True,check=False)
        self.assertEqual(invalid.returncode, 2)
        self.assertEqual(invalid.stderr, "")
        self.assertEqual(json.loads(invalid.stdout)["code"], "invalid_arguments")


if __name__ == "__main__":
    unittest.main()
