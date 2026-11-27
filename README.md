# WoW Forever squad addons

A lean default for questing together: readable frames and buff timers, quest and map help, bags, Auctionator, DBM and party quest sharing. Leveling dashboards, meters, gear scoring, voices and farming tools are optional.

## Install or update

Fully quit WoW first. Rerun this command even if you used the old installer; it adds profile support and the shared UI preset.

Windows: open PowerShell, with no admin rights needed, and paste:

```powershell
irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

Mac or Linux, including Steam Deck desktop mode and Bazzite: open Terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 -
```

Mac needs Python 3. The installer finds WoW in `/Applications/World of Warcraft` or `~/Applications/World of Warcraft`. If it cannot find your installation, specify the folder containing `_forever_`:

```powershell
$env:WOW_FOREVER_ROOT = 'D:\Games\World of Warcraft'
irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 - --wow-root "/path/to/World of Warcraft"
```

After installation finishes, launch WoW through Battle.net.

## Choose the UI preset

In game, type `/squadui` and choose Apply preset, then Reload. Until you choose Apply, the companion addon leaves your UI and enabled addons as they are.

The preset enlarges buff and debuff icons and countdown text, puts player and target frames below the character, and makes DBM text and bars more readable. It uses the native quest tracker, keeps Questie map markers, and quiets QuestTogether's announcements and extra quest display. Party quest sharing stays available.

It also turns off the optional addons listed below for your current character. Their files and saved data stay on disk. You can enable individual extras again in the game's AddOns menu.

Appearance changes use each addon's active profile, which may be shared by your other characters. `/squadui undo` restores the settings and addon choices captured before Apply, including your previous frame positions. Undo also replaces any later edits to those same fields. `/squadui status` shows whether the preset has been applied. The preset runs once when you choose it and keeps your later adjustments on future logins.

Apply it on each character that wants the preset. For a different screen size, undo and apply again to place the frames using the current screen dimensions. Controller bindings stay yours.

## Default pack

The `squad` profile installs 14 CurseForge projects and the Squad UI companion:

- X-Perl UnitFrames, including its buff countdown module, and Threat Plates.
- Questie with QuestieDB, OpenMap, What's Training? and Leatrix Plus.
- Baganator with Syndicator, Auctionator, DBM core and DBM dungeons.
- QuestTogether and EasyMarks Forever.

QuestieDB and Syndicator supply required data for Questie and Baganator. Keep both enabled.

OpenMap: press `M`, scroll to zoom, and drag to pan. `/openmap` opens its options. For quest markers that were hidden in your previous settings, check `/questie`; applying the preset preserves your map visibility choice.

EasyMarks: select a mob and double-left-click outside combat, or type `/emf`. For combat, bind Toggle raid marker wheel under Options > Keybindings > EasyMarks Forever. `/emf world` opens ground markers when you have group marking permission. No keys are assigned automatically.

## Optional extras

The full profile adds the other 23 projects: Road To Sixty, Lore Forever and its voice packs, GearQuest, DungeonJournal, Forever Quest Tint, Details!, Does It Die, SkillUp, Shortest Path, Books on Map, High Fidelity World Map, Lueur, LootOptimizer, BuffRadar, Chronicle, Podium, LevelUpCalculator, savyUI with Aura Tracker and Reminders, and Better Fishing. The voice packs alone add about 716 MB.

To install and update all extras on Mac or Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 - --profile full
```

On Windows:

```powershell
$env:WOW_FOREVER_PROFILE = 'full'
irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

Your selection is saved for future updates. To return to the lean profile, rerun with `--profile squad` on Mac/Linux or `$env:WOW_FOREVER_PROFILE = 'squad'` on Windows. Existing optional addon folders stay installed. Apply `/squadui` to turn them off for a character, or use the game's AddOns menu. If you already applied the preset, enable any extras you want afterward.

For just one extra, install its Forever release from CurseForge and enable it in AddOns. The squad updater leaves it in place. It updates projects included in your chosen profile.

Better Fishing: equip a fishing pole and bind Cast and Interact under Options > Keybindings > Better Fishing. Press to cast, then press again when the bobber bites. `/bf` opens its options. No fishing key is assigned automatically.

## Updates and saved data

The catalog is [`addons.json`](addons.json). CurseForge downloads use Forever builds only. Squad UI comes from this repository, with its SHA-256 checked before installation. Rerunning the installer updates the sync script; routine syncs fetch the current catalog and addon packages.

The updater writes to `_forever_/Interface/AddOns`. Auction prices, character settings, macros and keybindings live in `_forever_/WTF` and stay there. The in-game UI preset changes only its documented settings after you apply it, and saves an undo snapshot for that character. An addon removed from your selected profile stays installed until you remove it yourself.

Windows checks at login and daily through the WoW Forever addons sync task. Linux uses the `wow-forever-addons.timer` user timer. On Mac, rerun the install command to update. Jeremy's separately configured Mac scheduler continues Tuesday and Friday at 6 p.m. Pacific, catches up after missed runs, and waits for WoW to close.

Mac/Linux updates keep rollback copies of changed folders, preserve the installed Auctionator disenchant patch, and keep a newer ForeverCore when a bundle contains an older copy. Windows checks for the running game before extracting updates. Fully restart WoW after installing new addon folders.

Local files and logs:

- Windows: `%LOCALAPPDATA%\wow-forever-addons\`.
- Mac/Linux: `~/.local/share/wow-forever-addons/`.

The local `config.json` stores `wow_root` and `profile`. On Mac/Linux, an `exclude_ids` array can skip individual projects, such as `"exclude_ids": [1701034]` for High Fidelity World Map. Preserve the other fields when editing it. Reinstalling preserves these choices.

If something fails, send the last lines of `sync.log` from that folder.

## Remove the updater

```powershell
$env:WOW_FOREVER_UNINSTALL = '1'
irm https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.ps1 | iex
```

```sh
curl -fsSL https://raw.githubusercontent.com/jerem-ai/wow-forever-addons/main/install.py | python3 - --uninstall
```

This removes the updater and its timer. Installed addons and WoW settings stay.

## Maintainer checks

Run `python3 -m unittest -v`, `lua5.1 test_squad_ui.lua`, and on Windows `./test_windows.ps1`. CI also downloads and checks every core and optional package. After editing `ui/SquadUI/`, rebuild `SquadUI.zip` with the `SquadUI/` top-level folder and update `ui_bundle.sha256` in `addons.json`. The Python tests check that the zip matches the source exactly.
