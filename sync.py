#!/usr/bin/env python3
"""Keep the group's WoW Forever addons installed and current on macOS and Linux.

install.py saves this file to ~/.local/share/wow-forever-addons/ and a systemd user timer
runs it at login and once a day. Each run reads addons.json from GitHub (the list only,
never code), installs anything new and updates anything with a newer Forever build.

  python3 sync.py [--wow-root PATH] [--find-only]
  python3 sync.py --check [--addons FILE] [--extra-ids ID ...]   (the GitHub canary)

Exit codes: 0 all good, 1 something failed, 2 WoW Forever not found.
"""
import argparse
import datetime
import fcntl
import glob
import json
import os
import pathlib
import re
import sys
import tempfile
import urllib.request
import zipfile

ADDONS_URL = "https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/addons.json"
FOREVER = 88568  # CurseForge gameVersionTypeId for WoW Forever (1.60.x)
UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/130.0 Safari/537.36")
DATA = pathlib.Path(os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser() / "wow-forever-addons"
WOW = "drive_c/Program Files (x86)/World of Warcraft"
STEAM_ROOTS = [
    "~/.local/share/Steam",
    "~/.steam/steam",
    "~/.var/app/com.valvesoftware.Steam/.local/share/Steam",  # Flatpak Steam
]
PATTERNS = [
    "/Applications/World of Warcraft",
    "~/Applications/World of Warcraft",
    f"/run/media/*/steamapps/compatdata/*/pfx/{WOW}",
    f"/run/media/*/*/steamapps/compatdata/*/pfx/{WOW}",
    f"~/Games/*/{WOW}",  # Lutris, native or Flatpak
    f"~/Games/Heroic/Prefixes/*/{WOW}",
    f"~/Games/Heroic/Prefixes/default/*/{WOW}",
    f"~/.local/share/bottles/bottles/*/{WOW}",
    f"~/.var/app/com.usebottles.bottles/data/bottles/bottles/*/{WOW}",  # Flatpak Bottles
    f"~/.var/app/net.lutris.Lutris/data/lutris/prefixes/*/{WOW}",
    f"~/.wine/{WOW}",
    "~/WoW",
]

log_lines = []


def say(msg):
    print(msg, flush=True)
    log_lines.append(msg)


def steam_libraries():
    """Every Steam library folder, including ones on other drives (libraryfolders.vdf)."""
    libs = set()
    for root in STEAM_ROOTS:
        root = pathlib.Path(root).expanduser()
        if not root.is_dir():
            continue
        libs.add(str(root))
        vdf = root / "steamapps" / "libraryfolders.vdf"
        if vdf.is_file():
            for path in re.findall(r'"path"\s+"([^"]+)"', vdf.read_text(errors="replace")):
                libs.add(path.replace("\\\\", "\\"))
    return libs


def find_wow_root(explicit):
    candidates = [explicit] if explicit else []
    for lib in steam_libraries():
        candidates += glob.glob(os.path.join(glob.escape(lib), "steamapps/compatdata/*/pfx", WOW))
    for pattern in PATTERNS:
        candidates += glob.glob(os.path.expanduser(pattern))
    found = {}
    for candidate in candidates:
        if not candidate:
            continue
        root = pathlib.Path(candidate).expanduser()
        for executable in ("Wow.exe", "World of Warcraft.app/Contents/MacOS/World of Warcraft"):
            path = root / "_forever_" / executable
            if path.is_file():
                found[root] = max(found.get(root, 0), path.stat().st_mtime)
    if not found:
        return None
    # Several prefixes can hold a copy; use the one the game ran from most recently.
    return max(found, key=found.get).resolve()


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def load_addons(source):
    """The addon list from GitHub, falling back to the last copy that loaded."""
    cache = DATA / "addons.cache.json"
    try:
        raw = pathlib.Path(source).read_bytes() if os.path.exists(source) else get(source)
        addons = json.loads(raw)["addons"]
        if os.path.exists(str(DATA)):
            cache.write_bytes(raw)
        return addons
    except Exception as e:
        cached = read_json(cache, None)
        if cached:
            say(f"WARNING addon list unreachable ({e}); using the copy from the last sync")
            return cached["addons"]
        raise


def pick_file(project_id):
    url = (f"https://www.curseforge.com/api/v1/mods/{project_id}/files?pageIndex=0&pageSize=50"
           f"&sort=dateCreated&sortDescending=true&gameVersionTypeId={FOREVER}")
    files = [f for f in json.loads(get(url))["data"] if FOREVER in f.get("gameVersionTypeIds", [])]
    for release_type in (1, 2, 3):  # release, then beta, then alpha
        match = [f for f in files if f.get("releaseType") == release_type]
        if match:
            return match[0]
    return None


def download(project_id, f, dest):
    data = get(f"https://www.curseforge.com/api/v1/mods/{project_id}/files/{f['id']}/download")
    if f.get("fileLength") and len(data) != f["fileLength"]:
        raise RuntimeError(f"download is {len(data)} bytes, expected {f['fileLength']}")
    dest.write_bytes(data)
    with zipfile.ZipFile(dest) as z:
        folders = set()
        for m in z.infolist():
            p = pathlib.PurePosixPath(m.filename)
            if p.is_absolute() or ".." in p.parts or "\\" in m.filename:
                raise ValueError(f"unsafe path in zip: {m.filename}")
            if len(p.parts) > 1:
                folders.add(p.parts[0])
    return sorted(folders)


def check(args):
    """Canary: every addon still resolves to a Forever file that downloads and unzips."""
    addons = json.loads(pathlib.Path(args.addons).read_text())["addons"]
    addons += [{"name": f"extra {i}", "curseforge_id": int(i)} for i in args.extra_ids]
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for a in addons:
            try:
                f = pick_file(a["curseforge_id"])
                if not f:
                    raise RuntimeError("no Forever file on CurseForge")
                folders = download(a["curseforge_id"], f, pathlib.Path(tmp) / "a.zip")
                if not folders:
                    raise RuntimeError("zip has no addon folder")
                say(f"OK      {a['name']}: {f['displayName']} ({', '.join(folders)})")
            except Exception as e:
                say(f"FAILED  {a['name']} ({a['curseforge_id']}): {e}")
                failed += 1
    return 1 if failed else 0


def sync(args):
    config = read_json(DATA / "config.json", {})
    root = find_wow_root(args.wow_root or config.get("wow_root"))
    if not root:
        say("WoW Forever not found (no native Mac app or Wow.exe in _forever_). Install it through Battle.net first, "
            "or rerun the install with --wow-root.")
        return 2
    addons_dir = root / "_forever_" / "Interface" / "AddOns"
    say(f"WoW Forever: {root}")
    if args.find_only:
        return 0

    addons_dir.mkdir(parents=True, exist_ok=True)
    if DATA.is_dir():  # one sync at a time; a second run waits, then finds everything current
        lock = open(DATA / "sync.lock", "w")
        fcntl.flock(lock, fcntl.LOCK_EX)
    state_path = DATA / "state.json"
    state = read_json(state_path, {})
    failed = 0
    with tempfile.TemporaryDirectory(prefix="wow-forever-addons-") as tmp:
        for a in load_addons(args.addons):
            name, pid = a["name"], str(a["curseforge_id"])
            try:
                f = pick_file(pid)
                if not f:
                    raise RuntimeError("no Forever file on CurseForge")
                have = state.get(pid, {})
                if have.get("file_id") == f["id"] and all((addons_dir / d).is_dir() for d in have.get("folders", [])):
                    say(f"CURRENT {name}: {f['displayName']}")
                    continue
                zip_path = pathlib.Path(tmp) / f"{pid}.zip"
                folders = download(pid, f, zip_path)
                with zipfile.ZipFile(zip_path) as z:
                    z.extractall(addons_dir)
                state[pid] = {"file_id": f["id"], "folders": folders}
                say(f"{'UPDATED' if have else 'OK     '} {name}: {f['displayName']}")
            except Exception as e:  # report and keep going with the rest
                say(f"FAILED  {name}: {e}")
                failed += 1
    if DATA.is_dir():
        state_path.write_text(json.dumps(state, indent=1))
    say(f"AddOns folder: {addons_dir}")
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wow-root")
    ap.add_argument("--find-only", action="store_true")
    ap.add_argument("--addons", default=ADDONS_URL, help="addon list URL or file")
    ap.add_argument("--check", action="store_true", help="canary: resolve and download only")
    ap.add_argument("--extra-ids", nargs="*", default=[])
    args = ap.parse_args()

    code = check(args) if args.check else sync(args)
    if DATA.is_dir() and not args.check:
        log = DATA / "sync.log"
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        old = log.read_text().splitlines()[-2000:] if log.exists() else []
        log.write_text("\n".join(old + [f"== {stamp} exit {code}"] + log_lines) + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
