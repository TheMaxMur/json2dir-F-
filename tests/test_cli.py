#!/usr/bin/env python3
"""Black-box tests: Python is a test driver, never an application dependency."""
import json
import os
from pathlib import Path
import random
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("JSON2DIR_BIN", ROOT / "json2dir")).resolve()
REFERENCE = os.environ.get("JSON2DIR_REFERENCE")


def invoke(directory, source, args=(), binary=BINARY, umask=0o022):
    data = source.encode() if isinstance(source, str) else source
    return subprocess.run(
        [str(binary), *args], input=data, cwd=directory,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15, umask=umask,
    )


def snapshot(directory):
    result = {}
    for base, dirs, files in os.walk(directory, followlinks=False):
        for name in dirs + files:
            path = Path(base) / name
            relative = str(path.relative_to(directory))
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode):
                result[relative] = ("link", os.readlink(path))
            elif stat.S_ISDIR(info.st_mode):
                result[relative] = ("directory", stat.S_IMODE(info.st_mode))
            else:
                result[relative] = ("file", path.read_bytes(), stat.S_IMODE(info.st_mode))
    return result


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="json2dir-fstar-test-")
        self.directory = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def run_json(self, source, success=True, **kwargs):
        if not isinstance(source, (str, bytes)):
            source = json.dumps(source, ensure_ascii=False)
        result = invoke(self.directory, source, **kwargs)
        self.assertEqual(result.returncode == 0, success, result.stderr.decode(errors="replace"))
        self.assertEqual(result.stdout, b"")
        if not success:
            self.assertTrue(result.stderr)
        return result

    def test_example(self):
        self.run_json((ROOT / "example-tree.json").read_bytes())
        self.assertEqual((self.directory / "greeting").read_text(), "Hello, world!")
        self.assertEqual((self.directory / "dir/subfile").read_text(), "Content.\n")
        self.assertTrue((self.directory / "dir/subdir").is_dir())
        self.assertEqual(os.readlink(self.directory / "symlink"), "target path")
        script = self.directory / "script"
        self.assertEqual(script.stat().st_mode & 0o111, 0o111)
        result = subprocess.run([str(script)], capture_output=True, check=True)
        self.assertEqual(result.stdout, b"Howdy!\n")

    def test_empty_and_whitespace(self):
        self.run_json(b" \r\n\t{} \t\r\n")
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_arguments(self):
        for args in [("--help",), ("x",), ("x", "y")]:
            with self.subTest(args=args):
                result = self.run_json("{}", success=False, args=args)
                self.assertIn(b"Usage:", result.stderr)

    def test_unicode_and_escapes(self):
        source = r'{"файл 😀":"Привет\n\t\b\f\r\"\\\/\u0000\uD7FF\ud83d\ude00"}'
        self.run_json(source)
        self.assertEqual((self.directory / "файл 😀").read_bytes(),
                         'Привет\n\t\b\f\r"\\/\x00\ud7ff😀'.encode())

    def test_every_unicode_boundary(self):
        values = [0, 0x7f, 0x80, 0x7ff, 0x800, 0xd7ff, 0xe000, 0xffff, 0x10000, 0x10ffff]
        for escaped in (True, False):
            text = "".join(map(chr, values))
            self.run_json(json.dumps({"unicode": text}, ensure_ascii=escaped))
            self.assertEqual((self.directory / "unicode").read_bytes(), text.encode())

    def test_invalid_json(self):
        sources = ["", "f", "3 4", "{}{}", '{"x":}', '{"x":"unterminated}',
                   '{"x":"line\nbreak"}', r'{"x":"\q"}', r'{"x":"\ud800"}',
                   r'{"x":"\udc00"}', r'{"x":"\ud800\u0041"}', r'{"x":"\u0xx0"}',
                   '{"x":01}', '{"x":-}', '{"x":1.}', '{"x":1e}', '{"x":+1}',
                   '{"x":NaN}', '{"x":Infinity}', '{"x":false,}', '[1,]', '{x:"y"}',
                   '{"x":null // comment\n}', '\ufeff{}']
        for source in sources:
            with self.subTest(source=source):
                self.run_json(source, success=False)
                self.assertEqual(list(self.directory.iterdir()), [])

    def test_invalid_utf8(self):
        for invalid in [b"\xff", b'\xc0\xaf', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'{"x":"\xe2\x82"}']:
            with self.subTest(invalid=invalid):
                self.run_json(invalid, success=False)
                self.assertEqual(list(self.directory.iterdir()), [])

    def test_number_range_is_validated_before_writes(self):
        for source in ['{"a":"unchanged","z":1e400}', '{"x":1e400,"x":"last"}',
                       '{"x":-1e400}', '{"x":' + '9' * 500 + '}']:
            with self.subTest(source=source):
                self.run_json(source, success=False)
                self.assertEqual(list(self.directory.iterdir()), [])

    def test_stdin_read_error(self):
        descriptor = os.open(self.directory, os.O_RDONLY)
        try:
            result = subprocess.run([str(BINARY)], cwd=self.directory, stdin=descriptor,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        finally:
            os.close(descriptor)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"couldn't read stdin", result.stderr)

    def test_top_level(self):
        for source in ['"x"', '[]', '0', '-1.25e+3', 'true', 'false', 'null']:
            with self.subTest(source=source):
                result = self.run_json(source, success=False)
                self.assertIn(b"expected provided JSON to be an object", result.stderr)

    def test_invalid_values(self):
        for value in [None, True, False, 7, 1.5, [], ["link"], ["link", 7],
                      ["script", "x", "y"], ["unknown", "x"], [{}, "x"]]:
            with self.subTest(value=value):
                self.run_json({"bad": value}, success=False)

    def test_path_validation(self):
        for key in ["", ".", "..", "/", "/root", "a/b", "./a", "../a", "a/../b", "a\x00b"]:
            with self.subTest(key=key):
                self.run_json({key: "x"}, success=False)
                self.assertEqual(list(self.directory.iterdir()), [])
        self.run_json({".hidden": "yes", "back\\slash": "yes", "-option": "yes"})

    def test_rust_path_normalization(self):
        self.run_json({"folder//./": {"child": "x"}}, success=False)
        self.run_json({"folder//": {}})
        self.run_json({"folder//./": {"child": "x"}})
        self.assertEqual((self.directory / "folder/child").read_text(), "x")
        self.run_json({"bad/": "x"}, success=False)

    def test_duplicates_and_order(self):
        self.run_json('{"x":3,"x":"last","z":"z","a":"a"}')
        self.assertEqual((self.directory / "x").read_text(), "last")
        self.run_json('{"z":"changed","a":null}', success=False)
        self.assertEqual((self.directory / "z").read_text(), "z")

    def test_replacement_and_directory_merge(self):
        self.run_json({"a": "old", "dir": {"old": "keep"}, "link": ["link", "a"]})
        self.run_json({"a": {}, "dir": {"new": "add"}, "link": "plain"})
        self.assertTrue((self.directory / "a").is_dir())
        self.assertEqual((self.directory / "dir/old").read_text(), "keep")
        self.assertEqual((self.directory / "dir/new").read_text(), "add")
        self.assertFalse((self.directory / "link").is_symlink())

    def test_directories_are_not_removed(self):
        for payload in ["file", ["script", "file"], ["link", "target"]]:
            with self.subTest(payload=payload):
                (self.directory / "dir").mkdir(exist_ok=True)
                self.run_json({"dir": payload}, success=False)
                self.assertTrue((self.directory / "dir").is_dir())

    def test_symlink_target_is_not_modified(self):
        for existing in ["target", "missing"]:
            target = self.directory / existing
            if existing == "target":
                target.write_text("untouched")
            (self.directory / "link").symlink_to(existing)
            self.run_json({"link": "new"})
            self.assertFalse((self.directory / "link").is_symlink())
            self.assertEqual((self.directory / "link").read_text(), "new")
            if target.exists():
                self.assertEqual(target.read_text(), "untouched")
            (self.directory / "link").unlink()

    def test_directory_symlink_is_replaced(self):
        outside = self.directory / "outside"
        outside.mkdir()
        (outside / "keep").write_text("untouched")
        (self.directory / "dir").symlink_to("outside")
        self.run_json({"dir": {"new": "created"}})
        self.assertFalse((self.directory / "dir").is_symlink())
        self.assertEqual((outside / "keep").read_text(), "untouched")
        self.assertFalse((outside / "new").exists())

    @unittest.skipIf(os.getuid() == 0, "root bypasses Unix permission checks")
    def test_unwritable_directory(self):
        child = self.directory / "locked"
        child.mkdir()
        child.chmod(0o500)
        try:
            result = self.run_json({"locked": {"file": "content"}}, success=False)
            self.assertIn(b"./locked/file", result.stderr)
        finally:
            child.chmod(0o700)

    @unittest.skipIf(os.getuid() == 0, "root bypasses Unix permission checks")
    def test_unsearchable_empty_directory(self):
        child = self.directory / "locked"
        child.mkdir()
        child.chmod(0o600)
        try:
            self.run_json({"locked": {}}, success=False)
            if REFERENCE:
                result = invoke(self.directory, '{"locked":{}}', binary=REFERENCE)
                self.assertNotEqual(result.returncode, 0)
        finally:
            child.chmod(0o700)

    def test_modes_respect_umask(self):
        for mask in [0o022, 0o077, 0o777]:
            self.run_json({"file": "x", "script": ["script", "x"]}, umask=mask)
            self.assertEqual(stat.S_IMODE((self.directory / "file").stat().st_mode), 0o666 & ~mask)
            self.assertEqual(stat.S_IMODE((self.directory / "script").stat().st_mode), (0o666 & ~mask) | 0o111)

    def test_nesting_limit(self):
        self.run_json('{"x":' * 128 + '{}' + '}' * 128, success=False)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_long_payload(self):
        content = "Привет 😀\x00\n" * 20000
        self.run_json({"big": content})
        self.assertEqual((self.directory / "big").read_bytes(), content.encode())

    @unittest.skipUnless(REFERENCE, "set JSON2DIR_REFERENCE for Rust differential tests")
    def test_differential(self):
        rng = random.Random(20261006)
        def tree(depth):
            out = {}
            for index in range(rng.randrange(1, 6)):
                key = f"{index}-" + rng.choice(["русский", "ascii", "😀", ".dot", "back\\slash"])
                kind = rng.randrange(4 if depth else 3)
                content = ''.join(rng.choice('ab\n\t\x00😀я"\\') for _ in range(rng.randrange(30)))
                out[key] = content if kind == 0 else ["script", content] if kind == 1 else ["link", "../target"] if kind == 2 else tree(depth - 1)
            return out
        cases = [json.dumps(tree(3), ensure_ascii=bool(i % 2)) for i in range(75)]
        cases += ['{}', '{"x":3,"x":"last"}', '{"a":null,"z":"late"}',
                  '{"dir/./":{}}', '{"dir/":"x"}', '{".":"x"}', '{"x":["oops","x"]}',
                  '{"bad":"\\ud800"}', '{"z":"x","a/b":"bad"}',
                  '{"x":1e400,"x":"last"}', '{"a":"x","z":-1e400}',
                  '{"x":0e99999}', '{"x":1e-99999,"x":"last"}']
        for source in cases:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as left, tempfile.TemporaryDirectory() as right:
                actual = invoke(left, source)
                expected = invoke(right, source, binary=REFERENCE)
                self.assertEqual(actual.returncode, expected.returncode)
                self.assertEqual(snapshot(left), snapshot(right))


if __name__ == "__main__":
    unittest.main(verbosity=2)
