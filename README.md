# WoW Forever addons

Installs our group's WoW Forever addons and keeps them current. You run one line once. After that your PC checks for new and updated addons at every login and once a day.

## Install

**Windows.** Open PowerShell (no admin needed) and paste:

```powershell
irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

**Linux** (Steam Deck desktop mode, Bazzite, other distros). Open a terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 -
```

The last line tells you how it went. If it says WoW Forever wasn't found, point it at your World of Warcraft folder (the one that holds `_forever_`):

```powershell
$env:WOW_FOREVER_ROOT = 'D:\Games\World of Warcraft'; irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 - --wow-root "/path/to/World of Warcraft"
```

## The addons

The list lives in [`addons.json`](addons.json). Right now: Road To Sixty, QuestTogether, EasyMarksForever, Lore Forever, GearQuest Forever, DungeonJournal, Forever Quest Tint, What's Training?, Threat Plates, Auctionator, DBM (core and dungeons), X-Perl UnitFrames, Questie with QuestieDB, Details!, Leatrix Plus, Baganator with Syndicator, Does It Die, SkillUp Forever, Shortest Path Forever, Books on Map Forever, High Fidelity World Map and Lore Forever's quest voices (male narrator and quest givers, about 716 MB, off until you turn on Speak quest dialogue in Lore Forever's Options). Each one downloads straight from CurseForge, the Forever build only.

QuestieDB supplies Questie's quest data. Syndicator supplies Baganator's inventory data. Both are separate addons and must stay in the list, since our sync installs only the projects listed here.

High Fidelity World Map adds an HD/SD button to the world map. Open the map with `M` and use that button to switch views. Its zone and cave views use the game's textures. The optional Art companion supplies higher-resolution continent and world maps as a separate download. After installing a new addon folder, quit WoW fully and launch it again to load it.

## What it puts on your PC

- Windows: `%LOCALAPPDATA%\wow-forever-addons\` (the sync script, its log and a record of what it installed) and a scheduled task named "WoW Forever addons sync".
- Linux: `~/.local/share/wow-forever-addons/` and a systemd user timer named `wow-forever-addons.timer`.

Each sync reads the addon list from this repo. It never downloads new code. The script only changes when you run the install line again.

It adds and updates addons in `_forever_\Interface\AddOns`. It never deletes anything there, so an addon dropped from the list stays until you remove it yourself.

## Something wrong?

Send the log: `%LOCALAPPDATA%\wow-forever-addons\sync.log` on Windows, `~/.local/share/wow-forever-addons/sync.log` on Linux.

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
