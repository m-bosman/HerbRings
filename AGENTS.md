# AGENTS.md

Notes for working on this repo (people and coding agents).

## What this is

A WoW: Forever addon (client 1.60.1, `## Interface: 16001`). It draws coloured rings on herb spawn points on the minimap, coloured by Herbalism skill-up chance. Spawn points come from QuestieDB at runtime.

Forever is not Classic Era and not Retail. Don't assume either API. If unsure, check how an addon that already works on Forever does it (Questie, Mastercraft, EllesmereUI).

## Layout

| File | What |
|------|------|
| `HerbRings.toc` | Load order, metadata. `Version` is `@project-version@`, filled in by the packager |
| `Difficulty.lua` | Colour logic, no WoW API |
| `Data.lua` | Herbs: name, variants, required skill, keyed by GatherMate2 node ID |
| `Sources.lua` | Reads spawns from QuestieDB (`ObjectDB.spawns(objectID)` → `{[areaId] = {{x, y}}}`, 0..100), plus your own finds (`HerbRingsFound`) |
| `Core.lua` | Rings, tooltips, own finds (saved on Herb Gathering / loot), settings defaults/migrations, slash commands |
| `Options.lua` | Esc > Options > AddOns panel |
| `Libs/` | LibStub, CallbackHandler, HereBeDragons (embedded, committed) |
| `spec/` | Tests (`busted`) and the fake WoW API they run against |
| `Media/` | `Ring.tga` (minimap ring), `Icon.tga` (AddOns list icon). `mkicon.py` regenerates the icon and logo |

## Things that bite

- **Minimap tooltip text is a secret value.** Addons can't read or change it. Always check `issecretvalue`/`canaccessvalue` before touching tooltip text (see `ReadText` in `Core.lua`).
- **Options panel taint.** No OnShow/OnHide/OnCommit/OnRefresh/OnDefault handlers on the panel. Addon code running while the game's Options window opens or closes can block Log Out / Exit. Build once at login, refresh via `ns.RefreshOptions()`.
- **Changing a default.** `CopyDefaults` only fills missing keys, so existing users keep the old value. To move people on the old default, add a one-time migration in `PLAYER_LOGIN` (see `migratedSize12`, `migratedRadius400`).
- **Only some things can be tested locally.** `busted` runs against a fake WoW API (`spec/wow.lua`). Tooltips, secret values, the options panel and what Forever's events actually pass still need testing in game.
- **`.toc` changes (icon, metadata) need a full game restart**, not `/reload`.

## Checks

Needs Lua 5.1 with `luacheck` and `busted` (`sudo apt install lua5.1 luarocks`, then `sudo luarocks --lua-version 5.1 install luacheck busted`).

```
luacheck .   # unused/misspelled variables, stray globals. WoW globals are listed in .luacheckrc
busted       # tests in spec/, against the fake WoW API in spec/wow.lua
```

A new WoW global in the code needs adding to `.luacheckrc`, and to `spec/wow.lua` if it runs at load or in a tested path.

## Testing in game

Copy the addon into the game:

```
cp -r Core.lua Data.lua Difficulty.lua Options.lua Sources.lua HerbRings.toc Libs Media \
  "/mnt/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/HerbRings/"
```

Then `/reload` in game. Useful commands: `/hrings status`, `/hrings debug on` (prints zone scans), `/hrings trace` (prints tooltip owner and text for 60 s).

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) GitHub Action (`.github/workflows/release.yml`). It only runs on tags; pushing to `main` releases nothing.

1. Add the new version to the top of `CHANGELOG.md`. It becomes the release notes.
2. Commit and push:
   ```
   git add -A
   git commit -m "..."
   git push origin main
   ```
3. Tag and push the tag (annotated, the packager needs that):
   ```
   git tag -a v0.8.0 -m "v0.8.0"
   git push origin v0.8.0
   ```
4. Watch the run under **Actions** on GitHub. The zip ends up under **Releases**, and on each site that's configured.

Redo a tag:

```
git tag -d v0.8.0
git push origin :refs/tags/v0.8.0
```

Also delete the GitHub release for that tag if one was created.

Versioning: `vMAJOR.MINOR.PATCH`. Bump minor for features, patch for fixes.

### Where it uploads

| Target | Needs |
|--------|-------|
| GitHub release | Nothing, always on |
| CurseForge | `## X-Curse-Project-ID:` in the toc + `CF_API_KEY` secret |
| Wago | `## X-Wago-ID:` in the toc + `WAGO_API_TOKEN` secret |
| WoWInterface | `## X-WoWI-ID:` in the toc + `WOWI_API_TOKEN` secret |

Secrets go in GitHub > Settings > Secrets and variables > Actions. A target without its ID and token is skipped.

### What goes in the zip

`.pkgmeta` controls it. Left out: `.github`, `.gitignore`, `README.md`, `AGENTS.md`, `.luacheckrc`, `spec/`, and the icon tooling (`Media/mkicon.py`, `Media/icon_preview.png`, `Media/logo_400.png`).

## Writing style

README, changelog and in-game text: short and plain. Say what it does, skip the selling.
