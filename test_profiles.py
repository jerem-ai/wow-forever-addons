import hashlib
import json
import pathlib
import tempfile
import unittest
import zipfile
from types import SimpleNamespace
from unittest.mock import patch

import sync


class SquadProfileTests(unittest.TestCase):
    def test_default_core_keeps_dependencies_and_full_keeps_every_extra(self):
        catalog = json.loads(pathlib.Path("addons.json").read_text())
        core = sync.catalog_addons(catalog)
        full = sync.catalog_addons(catalog, "full")
        self.assertEqual(len(core), 15)
        self.assertEqual(len(full), 38)
        core_ids = {a.get("curseforge_id") for a in core}
        self.assertTrue({334372, 1696795, 914482, 988370, 3358, 314994} <= core_ids)
        self.assertFalse({61284, 1698950, 1208323, 1727331, 1731403, 1722589} & core_ids)
        all_ids = [a["curseforge_id"] for a in full if "curseforge_id" in a]
        self.assertEqual(len(all_ids), len(set(all_ids)))
        self.assertEqual(sync.catalog_addons({"addons": [{"name": "legacy"}]}, "full"), [{"name": "legacy"}])
        with self.assertRaises(ValueError):
            sync.catalog_addons(catalog, "unknown")

    def test_bundle_matches_reviewed_source_and_catalog_checksum(self):
        catalog = json.loads(pathlib.Path("addons.json").read_text())
        pid, meta = sync.resolve_addon(catalog["ui_bundle"])
        archive = pathlib.Path("SquadUI.zip")
        self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), meta["sha256"])
        with zipfile.ZipFile(archive) as z:
            expected = {str(p.relative_to("ui")) for p in pathlib.Path("ui/SquadUI").iterdir()}
            self.assertEqual(set(z.namelist()), expected)
            for name in z.namelist():
                self.assertEqual(z.read(name), (pathlib.Path("ui") / name).read_bytes())
            self.assertIsNone(z.testzip())
        self.assertEqual(pid, "SquadUI")
        with self.assertRaises(ValueError):
            sync.resolve_addon({"bundle": "../other", "sha256": "0" * 64})

    def test_checksum_failure_cannot_reach_install_and_valid_bundle_installs(self):
        catalog = json.loads(pathlib.Path("addons.json").read_text())
        _, meta = sync.resolve_addon(catalog["ui_bundle"])
        data = pathlib.Path("SquadUI.zip").read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            dest = root / "addon.zip"
            with patch.object(sync, "get", return_value=data + b"changed"):
                with self.assertRaisesRegex(ValueError, "checksum"):
                    sync.download("SquadUI", meta, dest)
            self.assertFalse(dest.exists())
            with patch.object(sync, "get", return_value=data):
                self.assertEqual(sync.download("SquadUI", meta, dest), ["SquadUI"])

    def test_native_bundle_install_is_idempotent_and_leaves_game_data_alone(self):
        bundle = json.loads(pathlib.Path("addons.json").read_text())["ui_bundle"]
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            root, data = base / "WoW", base / "data"
            data.mkdir()
            settings = root / "_forever_/WTF/Account/example/SavedVariables/Auctionator.lua"
            settings.parent.mkdir(parents=True)
            settings.write_text("preserve auction prices and preferences")
            catalog = base / "catalog.json"
            catalog.write_text(json.dumps({"addons": [], "ui_bundle": bundle}))
            args = SimpleNamespace(wow_root=None, find_only=False, addons=str(catalog))
            with patch.object(sync, "DATA", data), patch.object(sync, "find_wow_root", return_value=root), \
                 patch.object(sync, "game_running", return_value=False), \
                 patch.object(sync, "UI_URL", pathlib.Path("SquadUI.zip").resolve().as_uri()):
                self.assertEqual(sync.sync(args), 0)
                with patch.object(sync, "download") as download:
                    self.assertEqual(sync.sync(args), 0)
                    download.assert_not_called()
            self.assertTrue((root / "_forever_/Interface/AddOns/SquadUI/SquadUI.lua").is_file())
            self.assertEqual(settings.read_text(), "preserve auction prices and preferences")


if __name__ == "__main__":
    unittest.main()
