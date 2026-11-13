# WoW Forever addons

Installs our group's WoW Forever addons. Windows and Linux check for updates at login and daily. On Mac, rerun the install command to update.

## Install

**Windows.** Open PowerShell (no admin needed) and paste:

```powershell
irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

**Mac or Linux** (Steam Deck desktop mode, Bazzite, other distros). Quit WoW, open Terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 -
```

On Mac, this finds WoW in `/Applications/World of Warcraft` or `~/Applications/World of Warcraft`. It needs Python 3. Relaunch WoW through Battle.net after the install finishes.

The last line tells you how it went. If it says WoW Forever wasn't found, point it at your World of Warcraft folder (the one that holds `_forever_`):

```powershell
$env:WOW_FOREVER_ROOT = 'D:\Games\World of Warcraft'; irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 - --wow-root "/path/to/World of Warcraft"
```

## The addons

The list lives in [`addons.json`](addons.json). Right now: Road To Sixty, QuestTogether, EasyMarksForever, Lore Forever, GearQuest Forever, DungeonJournal, Forever Quest Tint, What's Training?, Threat Plates, Auctionator, DBM (core and dungeons), X-Perl UnitFrames, Questie with QuestieDB, Details!, Leatrix Plus, Baganator with Syndicator, Does It Die, SkillUp Forever, Shortest Path Forever, Books on Map Forever, High Fidelity World Map, OpenMap and Lore Forever's quest voices (male narrator and quest givers, about 716 MB, off until you turn on Speak quest dialogue in Lore Forever's Options). Each one downloads straight from CurseForge, the Forever build only.

QuestieDB supplies Questie's quest data. Syndicator supplies Baganator's inventory data. Both are separate addons and must stay in the list, since our sync installs only the projects listed here.

High Fidelity World Map adds an HD/SD button to the world map. Open the map with `M` and use that button to switch views. Its zone and cave views use the game's textures. The optional Art companion supplies higher-resolution continent and world maps as a separate download. After installing a new addon folder, quit WoW fully and launch it again to load it.

## OpenMap and marking

OpenMap adds a continuous world map. Press `M`, scroll to zoom and drag to pan; `/openmap` opens its options. The current Forever release supports Questie 12.8, Books on Map and High Fidelity World Map. OpenMap hides High Fidelity's overlay while its continuous map is showing and restores it on other maps. Fully quit and restart WoW after the first install.

EasyMarks Forever opens a marker wheel when needed. Select a mob and type `/emf`, or double-left-click a mob outside combat. Under Options > Keybindings > EasyMarks Forever, bind **Toggle raid marker wheel** to use it in combat. `/emf world` opens ground markers; these need a group and marking permission. `/emf status` shows its status. No keys are assigned automatically.

## What it puts on your PC

- Windows: `%LOCALAPPDATA%\wow-forever-addons\` (the sync script, its log and a record of what it installed) and a scheduled task named "WoW Forever addons sync".
- Linux: `~/.local/share/wow-forever-addons/` and a systemd user timer named `wow-forever-addons.timer`.
- Mac: `~/.local/share/wow-forever-addons/`. Rerun the install command to check for updates.

Each sync reads the addon list from this repo. It never downloads new code. The script only changes when you run the install line again.

It adds and updates addons in `_forever_\Interface\AddOns`. It never deletes anything there, so an addon dropped from the list stays until you remove it yourself.

## Something wrong?

Send the log: `%LOCALAPPDATA%\wow-forever-addons\sync.log` on Windows, `~/.local/share/wow-forever-addons/sync.log` on Mac or Linux.

## Remove it

```powershell
$env:WOW_FOREVER_UNINSTALL = '1'; irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 - --uninstall
```

This removes the task or timer and the script folder. Your addons stay.

## WowUp-CF

Not needed, since the sync does its job. To install it anyway on Windows, set `$env:WOW_FOREVER_WOWUP = '1'` before the install line.
