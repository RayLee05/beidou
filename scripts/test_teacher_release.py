"""Check teacher package selection and reject ambiguous streaming contracts."""
from pathlib import Path
import json
import tempfile
import unittest
from teacher_release import resolve_release, stream_config


def package(path, samples=16, earliest=True):
    (path / "input").mkdir(parents=True)
    (path / "sim").mkdir()
    (path / "sim/if2_file_player.sv").write_text("// test producer", encoding="utf-8")
    (path / "input/input_contract.json").write_text(json.dumps({
        "stream_player_contract": {"samples_per_transfer": samples,
                                   "stream_data_bit_1_0_is_earliest_sample": earliest}}), encoding="utf-8")
    return path


class TeacherReleaseTests(unittest.TestCase):
    def test_new_nested_package_precedes_original(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = package(root / "student_release", 4)
            self.assertEqual(resolve_release(root=root), original.resolve())
            updated = package(root / "student_release1/student_release")
            self.assertEqual(resolve_release(root=root), updated.resolve())
            self.assertEqual(resolve_release(root / "student_release1"), updated.resolve())
            self.assertEqual(resolve_release(original), original.resolve())

    def test_missing_package_does_not_silently_use_another(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            package(root / "student_release1/student_release")
            with self.assertRaises(ValueError): resolve_release(root / "missing", root=root)

    def test_current_and_four_sample_contracts(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            current = stream_config(package(root / "new"))
            self.assertEqual((current["rtl_mode"], current["tag_stride"], current["samples_per_transfer"]), (2, 16, 16))
            legacy = stream_config(package(root / "four", 4))
            self.assertEqual((legacy["rtl_mode"], legacy["tag_stride"], legacy["samples_per_transfer"]), (0, 4, 4))

    def test_unsupported_contract_requires_explicit_selection(self):
        with tempfile.TemporaryDirectory() as folder:
            release = package(Path(folder) / "new", 16, False)
            with self.assertRaises(ValueError): stream_config(release)
            self.assertEqual(stream_config(release, "legacy16")["rtl_mode"], 1)

    def test_invalid_and_explicit_tag_stride(self):
        with tempfile.TemporaryDirectory() as folder:
            release = package(Path(folder) / "new")
            for stride in (0, 3, 32):
                with self.subTest(stride=stride), self.assertRaises(ValueError):
                    stream_config(release, tag_stride=stride)
            self.assertEqual(stream_config(release, tag_stride=8)["tag_stride"], 8)


if __name__ == "__main__":
    unittest.main(verbosity=2)
