#!/usr/bin/env python3
"""Check every 15 minutes; sync once per Tuesday/Friday slot when WoW is closed."""
import datetime
import fcntl
import pathlib
import subprocess
import sys
from zoneinfo import ZoneInfo

import sync

ZONE = ZoneInfo("America/Los_Angeles")
HOUR = 18


def latest_slot(now):
    now = now.astimezone(ZONE)
    for offset in range(8):
        slot = (now - datetime.timedelta(days=offset)).replace(hour=HOUR, minute=0, second=0, microsecond=0)
        if slot.weekday() in (1, 4) and slot <= now:
            return slot


def main():
    sync.DATA.mkdir(parents=True, exist_ok=True)
    with (sync.DATA / "schedule.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        now = datetime.datetime.now(ZONE)
        slot = latest_slot(now)
        ledger = sync.DATA / "schedule-state.json"
        state = sync.read_json(ledger, {})
        if state.get("last_slot") and datetime.datetime.fromisoformat(state["last_slot"]) >= slot:
            return 0
        config = sync.read_json(sync.DATA / "config.json", {})
        root = sync.find_wow_root(config.get("wow_root"))
        if not root:
            print("FAILED scheduled sync: WoW installation not found", flush=True)
            return 2
        if sync.game_running(root):
            print(f"DEFERRED {slot.isoformat()}: WoW is open", flush=True)
            return 0
        print(f"START {slot.isoformat()}", flush=True)
        code = subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name("sync.py"))]).returncode
        if code != 0:
            print(f"PENDING {slot.isoformat()}: sync exit {code}", flush=True)
            return 0 if code == 75 else code
        pending = ledger.with_suffix(".json.tmp")
        pending.write_text(sync.json.dumps({"last_slot": slot.isoformat(),
                                          "completed_at": datetime.datetime.now(ZONE).isoformat()}, indent=2) + "\n")
        pending.replace(ledger)
        print(f"DONE {slot.isoformat()}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
