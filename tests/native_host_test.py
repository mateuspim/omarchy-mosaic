"""Tests for bin/mosaic-native-host: python3 tests/native_host_test.py"""

import importlib.machinery
import importlib.util
import io
import json
import os
import struct
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOADER = importlib.machinery.SourceFileLoader("mosaic_native_host", os.path.join(ROOT, "bin", "mosaic-native-host"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
host = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(host)

def load(path):
    with open(path) as file:
        return json.load(file)


def read(path):
    with open(path) as file:
        return file.read()


OMARCHY = "/usr/share/omarchy/default/chromium/extensions/copy-url,/usr/share/omarchy/default/chromium/extensions/yt-dlp"


class Flags(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.extension = os.path.join(self.scratch.name, "plugins", "pym.mosaic", "extension")
        os.makedirs(self.extension)
        with open(os.path.join(self.extension, "manifest.json"), "w") as file:
            json.dump({"name": "Omarchy Mosaic"}, file)

    def tearDown(self):
        self.scratch.cleanup()

    def test_appends_to_the_existing_line(self):
        text = "--ozone-platform=wayland\n--load-extension=" + OMARCHY + "\n"
        self.assertEqual(host.with_extension(text, self.extension),
                         "--ozone-platform=wayland\n--load-extension=" + OMARCHY + "," + self.extension + "\n")

    def test_adds_a_line_when_there_is_none(self):
        self.assertEqual(host.with_extension("--a\n", self.extension), "--a\n--load-extension=" + self.extension + "\n")
        self.assertEqual(host.with_extension("--a", self.extension), "--a\n--load-extension=" + self.extension + "\n")
        self.assertEqual(host.with_extension("", self.extension), "--load-extension=" + self.extension + "\n")

    def test_is_idempotent_and_replaces_a_moved_plugin(self):
        once = host.with_extension("--load-extension=" + OMARCHY + "\n", self.extension)
        self.assertEqual(host.with_extension(once, self.extension), once)
        moved = "--load-extension=" + OMARCHY + ",/gone/plugins/pym.mosaic/extension\n"
        self.assertEqual(host.with_extension(moved, self.extension),
                         "--load-extension=" + OMARCHY + "," + self.extension + "\n")

    def test_extends_the_last_line(self):
        text = "--load-extension=/a\n--x\n--load-extension=/b\n"
        self.assertEqual(host.with_extension(text, self.extension),
                         "--load-extension=/a\n--x\n--load-extension=/b," + self.extension + "\n")

    def test_removal_keeps_other_extensions(self):
        text = "--a\n--load-extension=" + OMARCHY + "," + self.extension + "\n"
        self.assertEqual(host.without_extension(text, self.extension), "--a\n--load-extension=" + OMARCHY + "\n")
        self.assertEqual(host.without_extension("--a\n--load-extension=" + self.extension + "\n", self.extension), "--a\n")
        self.assertEqual(host.without_extension("--load-extension=" + OMARCHY + "\n", ""), "--load-extension=" + OMARCHY + "\n")

    def test_loads_extension(self):
        self.assertTrue(host.loads_extension("--load-extension=/a," + self.extension + "\n", self.extension))
        self.assertFalse(host.loads_extension("--load-extension=/a\n", self.extension))
        self.assertFalse(host.loads_extension("# --load-extension=" + self.extension + "\n", self.extension))
        self.assertFalse(host.loads_extension("--load-extension=/a\n", ""))


class Setup(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.config = os.path.join(self.scratch.name, "config")
        os.makedirs(os.path.join(self.config, "BraveSoftware", "Brave-Origin"))
        os.makedirs(os.path.join(self.config, "chromium"))
        self.extension = os.path.join(ROOT, "extension")
        self.saved = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = self.config
        # The flags file is a symlink, as in a dotfiles checkout.
        self.real_flags = os.path.join(self.scratch.name, "dotfiles-brave-origin-flags.conf")
        with open(self.real_flags, "w") as file:
            file.write("--ozone-platform=wayland\n--load-extension=" + OMARCHY + "\n")
        os.chmod(self.real_flags, 0o600)
        os.symlink(self.real_flags, os.path.join(self.config, "brave-origin-flags.conf"))

    def tearDown(self):
        if self.saved is None:
            del os.environ["XDG_CONFIG_HOME"]
        else:
            os.environ["XDG_CONFIG_HOME"] = self.saved
        self.scratch.cleanup()

    def test_setup_status_and_remove(self):
        before = host.status(self.extension)
        self.assertEqual([b["name"] for b in before["browsers"]], ["Brave Origin", "Chromium"])
        self.assertFalse(any(b["registered"] for b in before["browsers"]))
        self.assertEqual(before["flags"], [{"file": os.path.join(self.config, "brave-origin-flags.conf"), "loaded": False}])

        host.setup(self.extension)
        after = host.status(self.extension)
        self.assertTrue(all(b["registered"] for b in after["browsers"]))
        self.assertTrue(after["flags"][0]["loaded"])
        # Only existing browsers and flags files are touched.
        self.assertFalse(os.path.exists(os.path.join(self.config, "google-chrome")))
        self.assertFalse(os.path.exists(os.path.join(self.config, "chromium-flags.conf")))
        # The symlink survives, and the real file changed with its mode kept.
        self.assertTrue(os.path.islink(os.path.join(self.config, "brave-origin-flags.conf")))
        self.assertIn("," + self.extension, read(self.real_flags))
        self.assertEqual(os.stat(self.real_flags).st_mode & 0o777, 0o600)
        manifest = load(os.path.join(self.config, "chromium", "NativeMessagingHosts", "pym.mosaic.json"))
        self.assertEqual(manifest["allowed_origins"], ["chrome-extension://" + host.EXTENSION_ID + "/"])
        self.assertTrue(os.access(manifest["path"], os.X_OK))

        host.remove(self.extension)
        removed = host.status(self.extension)
        self.assertFalse(any(b["registered"] for b in removed["browsers"]))
        self.assertFalse(removed["flags"][0]["loaded"])
        self.assertEqual(read(self.real_flags), "--ozone-platform=wayland\n--load-extension=" + OMARCHY + "\n")

    def test_setup_refuses_bad_folders(self):
        with self.assertRaises(SystemExit):
            host.setup("relative/extension")
        with self.assertRaises(SystemExit):
            host.setup("/a,b/extension")
        with self.assertRaises(SystemExit):
            host.setup(self.scratch.name)

    def test_the_extension_id_matches_the_key(self):
        import base64
        import hashlib
        key = load(os.path.join(self.extension, "manifest.json"))["key"]
        digest = hashlib.sha256(base64.b64decode(key)).hexdigest()[:32]
        self.assertEqual("".join(chr(ord("a") + int(c, 16)) for c in digest), host.EXTENSION_ID)


class Relay(unittest.TestCase):
    def test_frames_messages_for_the_browser(self):
        relay = host.Relay()
        out = io.BytesIO()
        saved = sys.stdout
        wrapper = io.TextIOWrapper(out)
        sys.stdout = wrapper
        try:
            relay.shell_line(b'{"type":"ping","id":3}')
            relay.shell_line(b"not json")
            relay.shell_line(b"[1,2]")
        finally:
            sys.stdout = saved
            wrapper.detach()
        data = out.getvalue()
        length = struct.unpack("<I", data[:4])[0]
        self.assertEqual(json.loads(data[4:4 + length]), {"type": "ping", "id": 3})
        self.assertEqual(len(data), 4 + length)

    def test_remembers_hello_and_windows_for_a_new_shell(self):
        relay = host.Relay()
        relay.from_browser({"type": "hello", "extension": "0.1.0"})
        relay.from_browser({"type": "windows", "windows": []})
        relay.from_browser({"type": "windows", "id": 4, "windows": [1]})
        self.assertEqual(relay.hello, {"type": "hello", "extension": "0.1.0"})
        self.assertEqual(relay.windows, {"type": "windows", "windows": []})


if __name__ == "__main__":
    unittest.main()
