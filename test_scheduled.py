import datetime
import json
import pathlib
import stat
import tempfile
import unittest
import zipfile
from types import SimpleNamespace
from unittest.mock import patch

import install
import scheduled_mac
import sync


class SafeUpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.addons = self.root / "WoW/_forever_/Interface/AddOns"
        self.addons.mkdir(parents=True)
        self.backup = self.root / "backup"
        self.guard = patch.object(sync, "game_running", return_value=False)
        self.guard.start()
        self.addCleanup(self.guard.stop)

    def archive(self, files):
        path = self.root / "new.zip"
        with zipfile.ZipFile(path, "w") as z:
            for name, data in files.items():
                z.writestr(name, data)
        return path

    def put(self, name, text):
        p = self.addons / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def apply(self, archive):
        return sync.install_archive(archive, self.addons, self.backup, self.root / "WoW")

    def test_rejects_traversal_but_accepts_addon_and_paths_with_spaces(self):
        with self.assertRaises(ValueError):
            self.apply(self.archive({"../outside.txt": "bad"}))
        self.assertFalse((self.root / "outside.txt").exists())
        self.apply(self.archive({"README.txt": "package notes", "Addon With Spaces/Locale/en US.lua": "valid"}))
        self.assertEqual((self.addons / "Addon With Spaces/Locale/en US.lua").read_text(), "valid")
        self.assertFalse((self.addons / "README.txt").exists())

    def test_rejects_zip_symlink(self):
        p = self.root / "link.zip"
        with zipfile.ZipFile(p, "w") as z:
            entry = zipfile.ZipInfo("Addon/link")
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            z.writestr(entry, "../../outside")
        with self.assertRaises(ValueError):
            self.apply(p)

    def test_keeps_newer_core_while_updating_its_consumer(self):
        self.put("ForeverCore/ForeverCore.toc", "## Version: v1.10.0")
        self.put("ForeverCore/api.lua", "newer")
        self.apply(self.archive({"ForeverCore/ForeverCore.toc": "## Version: v1.9.0",
                                 "ForeverCore/api.lua": "older", "SkillUpForever/main.lua": "updated"}))
        self.assertEqual((self.addons / "ForeverCore/api.lua").read_text(), "newer")
        self.assertEqual((self.addons / "SkillUpForever/main.lua").read_text(), "updated")
        self.apply(self.archive({"ForeverCore/ForeverCore.toc": "## Version: v1.11.0",
                                 "ForeverCore/api.lua": "newest"}))
        self.assertEqual((self.addons / "ForeverCore/api.lua").read_text(), "newest")
        self.assertEqual((self.backup / "ForeverCore/api.lua").read_text(), "newer")

    def test_preserves_existing_disenchant_patch(self):
        load = "Source_Classic\\Enchant\\Manifest.xml [AllowLoadGameType camelot][ExcludeLoadGameType classic, standard]"
        self.put("Auctionator/Auctionator.toc", "## Version: 345\n" + load)
        self.apply(self.archive({"Auctionator/Auctionator.toc": "## Version: 346",
                                 "Auctionator/Source_Classic/Enchant/Manifest.xml": "<Ui/>",
                                 "Auctionator/Source_Classic/Enchant/Main.lua": "Enum.ItemQuality.Good",
                                 "Auctionator/Source_Classic/Enchant/DisenchantingProbabilities.lua": "Enum.ItemQuality.Good"}))
        self.assertEqual((self.addons / "Auctionator/Auctionator.toc").read_text().count(load), 1)
        self.assertEqual((self.addons / "Auctionator/Source_Classic/Enchant/Main.lua").read_text(),
                         "Enum.ItemQuality.Uncommon")

    def test_game_open_defers_without_touching_installed_files(self):
        self.put("Addon/main.lua", "old")
        with patch.object(sync, "game_running", return_value=True), self.assertRaises(BlockingIOError):
            self.apply(self.archive({"Addon/main.lua": "new"}))
        self.assertEqual((self.addons / "Addon/main.lua").read_text(), "old")

    def test_failed_second_folder_restores_both_originals(self):
        self.put("A/main.lua", "old A")
        self.put("B/main.lua", "old B")
        native = pathlib.Path.rename

        def fail_second(path, target):
            if path.name == "B" and path.parent.name == "new":
                raise OSError("simulated replacement failure")
            return native(path, target)

        with patch.object(pathlib.Path, "rename", fail_second), self.assertRaises(OSError):
            self.apply(self.archive({"A/main.lua": "new A", "B/main.lua": "new B"}))
        for folder in ("A", "B"):
            self.assertEqual((self.addons / folder / "main.lua").read_text(), "old " + folder)
            self.assertEqual((self.backup / folder / "main.lua").read_text(), "old " + folder)

    def test_process_guard_requires_exact_executable(self):
        self.guard.stop()
        executable = "/Applications/World of Warcraft/_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft"
        with patch.object(sync.sys, "platform", "darwin"):
            with patch.object(sync.subprocess, "check_output", return_value="python probe " + executable):
                self.assertFalse(sync.game_running(pathlib.Path("/Applications/World of Warcraft")))
            with patch.object(sync.subprocess, "check_output", return_value=executable + "\n"):
                self.assertTrue(sync.game_running(pathlib.Path("/Applications/World of Warcraft")))

    def test_partial_sync_persists_completed_addon_before_deferring(self):
        data = self.root / "data"
        data.mkdir()
        (data / "state.json").write_text(json.dumps({"1": {"file_id": 1, "folders": ["A"]},
                                                   "2": {"file_id": 1, "folders": ["B"]}}))
        self.put("A/main.lua", "old A")
        self.put("B/main.lua", "old B")

        def download(pid, meta, dest):
            folder = "A" if pid == "1" else "B"
            with zipfile.ZipFile(dest, "w") as z:
                z.writestr(folder + "/main.lua", "new " + folder)

        with patch.object(sync, "DATA", data), \
             patch.object(sync, "find_wow_root", return_value=self.root / "WoW"), \
             patch.object(sync, "load_addons", return_value=[{"name": n, "curseforge_id": p} for n, p in [("A", 1), ("B", 2)]]), \
             patch.object(sync, "pick_file", return_value={"id": 2, "displayName": "new"}), \
             patch.object(sync, "download", side_effect=download), \
             patch.object(sync, "game_running", side_effect=[False, False, False, True]):
            self.assertEqual(sync.sync(SimpleNamespace(wow_root=None, find_only=False, addons="unused")), 75)
        state = json.loads((data / "state.json").read_text())
        self.assertEqual(state["1"]["file_id"], 2)
        self.assertEqual(state["2"]["file_id"], 1)
        self.assertEqual((self.addons / "B/main.lua").read_text(), "old B")


class ScheduleTests(unittest.TestCase):
    def test_slots_wait_for_tuesday_and_friday_and_keep_pacific_time(self):
        zone = scheduled_mac.ZONE
        tuesday = datetime.datetime(2026, 11, 17, 18, tzinfo=zone)
        self.assertEqual(scheduled_mac.latest_slot(tuesday), tuesday)
        self.assertEqual(scheduled_mac.latest_slot(tuesday - datetime.timedelta(minutes=1)).weekday(), 4)
        friday = datetime.datetime(2026, 11, 20, 18, tzinfo=zone)
        self.assertEqual(scheduled_mac.latest_slot(friday.astimezone(datetime.timezone.utc)), friday)
        self.assertEqual(scheduled_mac.latest_slot(datetime.datetime(2026, 3, 10, 18, tzinfo=zone)).utcoffset(),
                         datetime.timedelta(hours=-7))

    def test_open_game_waits_success_records_slot_and_duplicate_run_does_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = pathlib.Path(tmp)
            slot = datetime.datetime(2026, 11, 13, 18, tzinfo=scheduled_mac.ZONE)
            with patch.object(sync, "DATA", data), patch.object(scheduled_mac, "latest_slot", return_value=slot), \
                 patch.object(sync, "find_wow_root", return_value=data / "WoW"), \
                 patch.object(sync, "game_running", return_value=True), \
                 patch.object(scheduled_mac.subprocess, "run") as run:
                self.assertEqual(scheduled_mac.main(), 0)
                run.assert_not_called()
                self.assertFalse((data / "schedule-state.json").exists())
            with patch.object(sync, "DATA", data), patch.object(scheduled_mac, "latest_slot", return_value=slot), \
                 patch.object(sync, "find_wow_root", return_value=data / "WoW"), \
                 patch.object(sync, "game_running", return_value=False), \
                 patch.object(scheduled_mac.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
                self.assertEqual(scheduled_mac.main(), 0)
                self.assertEqual(scheduled_mac.main(), 0)
                run.assert_called_once()
                self.assertEqual(json.loads((data / "schedule-state.json").read_text())["last_slot"], slot.isoformat())

    def test_failed_sync_stays_pending(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = pathlib.Path(tmp)
            with patch.object(sync, "DATA", data), patch.object(sync, "find_wow_root", return_value=data / "WoW"), \
                 patch.object(sync, "game_running", return_value=False), \
                 patch.object(scheduled_mac.subprocess, "run", return_value=SimpleNamespace(returncode=1)):
                self.assertEqual(scheduled_mac.main(), 1)
                self.assertFalse((data / "schedule-state.json").exists())

    def test_uninstall_removes_mac_agent(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = pathlib.Path(tmp)
            data, agent = p / "data", p / "agent.plist"
            data.mkdir()
            agent.touch()
            with patch.object(install, "DATA", data), patch.object(install, "MAC_AGENT", agent), \
                 patch.object(install, "UNITS", p / "units"), patch.object(install.sys, "platform", "darwin"), \
                 patch.object(install.shutil, "which", return_value=None), \
                 patch.object(install.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run:
                self.assertEqual(install.uninstall(), 0)
                run.assert_called_once()
            self.assertFalse(agent.exists())
