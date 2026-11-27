import io
import json
import pathlib
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import install
import sync


class MacInstallTests(unittest.TestCase):
    def test_reinstall_preserves_full_profile_and_can_switch_back_to_squad(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = pathlib.Path(tmp)
            config = data / "config.json"
            config.write_text(json.dumps({"wow_root": "keep", "exclude_ids": [1701034], "profile": "full"}))
            for argv, expected in [(["install.py"], "full"), (["install.py", "--profile", "squad"], "squad")]:
                with patch.object(install, "DATA", data), patch.object(install.sys, "argv", argv), \
                     patch.object(install.urllib.request, "urlopen", return_value=io.BytesIO(b"# sync")), \
                     patch.object(install.subprocess, "run", return_value=SimpleNamespace(returncode=0)), \
                     patch.object(install.shutil, "which", return_value=None):
                    self.assertEqual(install.main(), 0)
                self.assertEqual(json.loads(config.read_text()),
                                 {"wow_root": "keep", "exclude_ids": [1701034], "profile": expected})

    def test_reinstall_with_wow_root_preserves_local_exclusions(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = pathlib.Path(tmp)
            config = data / "config.json"
            config.write_text(json.dumps({"wow_root": "old", "exclude_ids": [1701034]}))
            with patch.object(install, "DATA", data), \
                 patch.object(install.sys, "argv", ["install.py", "--wow-root", "/Applications/World of Warcraft"]), \
                 patch.object(install.urllib.request, "urlopen", return_value=io.BytesIO(b"# sync")), \
                 patch.object(install.subprocess, "run", return_value=SimpleNamespace(returncode=0)), \
                 patch.object(install.shutil, "which", return_value=None):
                self.assertEqual(install.main(), 0)
            self.assertEqual(json.loads(config.read_text()),
                             {"wow_root": "/Applications/World of Warcraft", "exclude_ids": [1701034], "profile": "squad"})

    def test_finds_native_mac_app_in_path_with_spaces(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / "World of Warcraft"
            executable = root / "_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft"
            executable.parent.mkdir(parents=True)
            executable.touch()
            with patch.object(sync, "PATTERNS", []), patch.object(sync, "steam_libraries", return_value=[]):
                self.assertEqual(sync.find_wow_root(str(root)), root.resolve())

    def test_discovers_mac_default_location_pattern(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp) / "Applications/World of Warcraft"
            executable = root / "_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft"
            executable.parent.mkdir(parents=True)
            executable.touch()
            with patch.object(sync, "PATTERNS", [str(root)]), patch.object(sync, "steam_libraries", return_value=[]):
                self.assertEqual(sync.find_wow_root(None), root.resolve())

    def test_keeps_windows_prefix_support(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "_forever_").mkdir()
            (root / "_forever_/Wow.exe").touch()
            with patch.object(sync, "PATTERNS", []), patch.object(sync, "steam_libraries", return_value=[]):
                self.assertEqual(sync.find_wow_root(str(root)), root.resolve())

    def test_rejects_empty_app_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "_forever_/World of Warcraft.app").mkdir(parents=True)
            with patch.object(sync, "PATTERNS", []), patch.object(sync, "steam_libraries", return_value=[]):
                self.assertIsNone(sync.find_wow_root(str(root)))

    def test_uninstall_without_systemd_leaves_addons_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            data = root / "sync-data"
            data.mkdir()
            addon = root / "_forever_/Interface/AddOns/Questie/Questie.toc"
            addon.parent.mkdir(parents=True)
            addon.write_text("test addon")
            with patch.object(install, "DATA", data), patch.object(install, "UNITS", root / "units"), patch.object(install, "MAC_AGENT", root / "agent.plist"), patch.object(install.shutil, "which", return_value=None):
                self.assertEqual(install.uninstall(), 0)
            self.assertFalse(data.exists())
            self.assertEqual(addon.read_text(), "test addon")


if __name__ == "__main__":
    unittest.main()
