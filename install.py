#!/usr/bin/env python3
"""Install the WoW Forever addon sync on Linux (Steam Deck, Bazzite). No sudo needed.

  curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 -
  ... | python3 - --wow-root "/path/to/World of Warcraft"
  ... | python3 - --uninstall

Saves sync.py to ~/.local/share/wow-forever-addons/, adds a systemd user timer that runs it
at login and once a day, then runs the first sync. Exit codes match sync.py.
"""
import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import urllib.request

REPO = "https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main"
DATA = pathlib.Path(os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser() / "wow-forever-addons"
UNITS = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser() / "systemd" / "user"
NAME = "wow-forever-addons"

SERVICE = """[Unit]
Description=Sync WoW Forever addons
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart="{python}" "{sync}"
"""

TIMER = """[Unit]
Description=Sync WoW Forever addons at login and daily

[Timer]
OnStartupSec=3min
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
"""


def systemctl(*args):
    return subprocess.run(["systemctl", "--user", *args], capture_output=True, text=True)


def uninstall():
    systemctl("disable", "--now", f"{NAME}.timer")
    for unit in (f"{NAME}.service", f"{NAME}.timer"):
        (UNITS / unit).unlink(missing_ok=True)
    systemctl("daemon-reload")
    shutil.rmtree(DATA, ignore_errors=True)
    print("Removed the sync timer and its files. Installed addons were left in place.")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wow-root")
    ap.add_argument("--uninstall", action="store_true")
    args = ap.parse_args()
    if args.uninstall:
        return uninstall()

    DATA.mkdir(parents=True, exist_ok=True)
    sync = DATA / "sync.py"
    with urllib.request.urlopen(f"{REPO}/sync.py", timeout=60) as r:
        sync.write_bytes(r.read())
    if args.wow_root:
        (DATA / "config.json").write_text(json.dumps({"wow_root": args.wow_root}))

    found = subprocess.run([sys.executable, str(sync), "--find-only"])
    if found.returncode == 2:
        return 2

    print("First sync:", flush=True)
    code = subprocess.run([sys.executable, str(sync)]).returncode

    if shutil.which("systemctl") and systemctl("is-system-running").stdout.strip():
        UNITS.mkdir(parents=True, exist_ok=True)
        (UNITS / f"{NAME}.service").write_text(SERVICE.format(python=sys.executable, sync=sync))
        (UNITS / f"{NAME}.timer").write_text(TIMER)
        systemctl("daemon-reload")
        enabled = systemctl("enable", "--now", f"{NAME}.timer")
        if enabled.returncode == 0:
            print("Daily sync on: systemd user timer wow-forever-addons.timer", flush=True)
        else:
            print(f"Could not turn on the daily sync: {enabled.stderr.strip()}", flush=True)
    else:
        print("No systemd user session here, so no daily sync. Rerun this installer to update.", flush=True)

    return code


if __name__ == "__main__":
    sys.exit(main())
