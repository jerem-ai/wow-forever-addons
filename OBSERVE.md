# OBSERVE

## Addon sync on a friend's PC

- Write site: `sync.py` `sync()` (Linux) and `sync.ps1` `Invoke-Sync` (Windows), into `<WoW>/_forever_/Interface/AddOns`.
- Observe: ask the friend for the last lines of the log.
  - Windows: `Get-Content "$env:LOCALAPPDATA\wow-forever-addons\sync.log" -Tail 30`
  - Linux: `tail -30 ~/.local/share/wow-forever-addons/sync.log; systemctl --user list-timers wow-forever-addons.timer`
- Shape: a `== <date> exit <code>` header, then one line per addon (`OK`, `UPDATED`, `CURRENT` or `FAILED`), then the AddOns folder.
- Healthy: a header from the last day with `exit 0`, and every addon `CURRENT` or `UPDATED`.

## Baganator and Questie dependencies

- Write site: the same sync installs Syndicator and QuestieDB from `addons.json` as separate addon folders.
- Observe on Linux:
  ```sh
  ls -d ~/WoW/_forever_/Interface/AddOns/{Baganator,Syndicator,Questie,QuestieDB}
  grep -hE '^## (Version|Interface):' ~/WoW/_forever_/Interface/AddOns/Syndicator/*.toc ~/WoW/_forever_/Interface/AddOns/QuestieDB/*Forever.toc
  tail -30 ~/.local/share/wow-forever-addons/sync.log
  ```
- Healthy: all four sibling folders exist, Syndicator and QuestieDB declare interface `16001` for Forever, and the log reports each dependency installed or current. Quit WoW fully and relaunch after installing new folders, then check that bags open and Questie draws quest markers without a missing dependency warning.

## High Fidelity World Map

- Write site: the sync installs CurseForge project `1701034` from `addons.json` into `HighFidelityWorldMap` and records its file ID in `state.json`.
- Observe on Linux:
  ```sh
  rg '^## (Interface|Version):' ~/WoW/_forever_/Interface/AddOns/HighFidelityWorldMap/HighFidelityWorldMap.toc
  python3 -c 'import json,pathlib; print(json.loads((pathlib.Path.home()/".local/share/wow-forever-addons/state.json").read_text()).get("1701034"))'
  tail -30 ~/.local/share/wow-forever-addons/sync.log
  ```
- Healthy: interface `16001`, an installed file ID in the sync state, and an `OK`, `UPDATED` or `CURRENT` log entry. After a full WoW restart, open the map with `M` and check the HD/SD toggle, quest markers and cave map. Files on disk alone do not verify the in-game view.

## CurseForge canary

- Write site: `.github/workflows/canary.yml`, daily at 15:17 UTC and on every push to `addons.json` or `sync.py`.
- Observe: `gh run list -R jerem-ai/wow-forever-addons -w canary.yml -L 5`
- Shape: one row per run with its status and trigger.
- Healthy: the newest scheduled run is under 26 hours old and passed. A failed run means friends' syncs are failing the same way.

## OpenMap

- Write site: the existing sync installs CurseForge project `1735937` from `addons.json` into `OpenMap` and records its file ID in `state.json`.
- Observe on Mac:
  ```sh
  rg '^## (Interface|Version):' "/Applications/World of Warcraft/_forever_/Interface/AddOns/OpenMap/OpenMap.toc"
  python3 -c 'import json,pathlib; print(json.loads((pathlib.Path.home()/".local/share/wow-forever-addons/state.json").read_text()).get("1735937"))'
  tail -30 ~/.local/share/wow-forever-addons/sync.log
  ```
- Healthy: interface `16001`, an installed file ID in the sync state, and an `OK`, `UPDATED` or `CURRENT` log entry. After a full WoW restart, `M` opens the continuous map, scroll and drag work, and Questie quest icons stay visible while zooming. Check High Fidelity's alternate-map overlay separately; source compatibility does not establish the live view.

## Scheduled Mac updates

- Write site: `scheduled_mac.py` calls the installed `sync.py` for each due Tuesday/Friday 10 a.m. Pacific slot. The sync writes addon folders and updater state, with rollback copies under `~/.local/share/wow-forever-addons/backups/sync/`.
- Observe:
  ```sh
  launchctl print gui/$(id -u)/com.jeremyshank.wow-forever-addons
  cat ~/.local/share/wow-forever-addons/schedule-state.json
  tail -40 ~/.local/share/wow-forever-addons/schedule.log
  tail -40 ~/.local/share/wow-forever-addons/sync.log
  ```
- Healthy: the launch agent is loaded with a 900-second interval. The ledger records the most recent completed scheduled slot. The logs show `DONE` and sync exit 0, or `DEFERRED` while WoW is open. No network update runs between completed slots. A failed sync leaves the slot pending. Code on disk still needs an in-game check after restarting WoW.
