# OBSERVE

## Addon sync on a friend's PC

- Write site: `sync.py` `sync()` (Linux) and `sync.ps1` `Invoke-Sync` (Windows), into `<WoW>/_forever_/Interface/AddOns`.
- Observe: ask the friend for the last lines of the log.
  - Windows: `Get-Content "$env:LOCALAPPDATA\wow-forever-addons\sync.log" -Tail 30`
  - Linux: `tail -30 ~/.local/share/wow-forever-addons/sync.log; systemctl --user list-timers wow-forever-addons.timer`
- Shape: a `== <date> exit <code>` header, then one line per addon (`OK`, `UPDATED`, `CURRENT` or `FAILED`), then the AddOns folder.
- Healthy: a header from the last day with `exit 0`, and every addon `CURRENT` or `UPDATED`.

## CurseForge canary

- Write site: `.github/workflows/canary.yml`, daily at 15:17 UTC and on every push to `addons.json` or `sync.py`.
- Observe: `gh run list -R jerem-ai/wow-forever-addons -w canary.yml -L 5`
- Shape: one row per run with its status and trigger.
- Healthy: the newest scheduled run is under 26 hours old and passed. A failed run means friends' syncs are failing the same way.
