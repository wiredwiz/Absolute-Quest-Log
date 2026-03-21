# Bundle LibStub and CallbackHandler-1.0 — Design Spec

**Date:** 2026-03-21
**Status:** Approved
**Project:** AbsoluteQuestLog (AQL)

---

## Goal

Remove AQL's dependency on the full Ace3 addon by bundling the only two Ace3 components it actually uses — LibStub and CallbackHandler-1.0 — directly inside the AQL addon folder. AQL becomes a self-contained library with zero external dependencies.

---

## Background

AQL's `.toc` currently declares `## Dependencies: Ace3`, pulling in the entire Ace3 suite (~15 libraries) at load time. An audit reveals only two of those libraries are used:

| Library | Usage |
|---|---|
| **LibStub** | `LibStub:NewLibrary(MAJOR, MINOR)` on line 6 of `AbsoluteQuestLog.lua` — registers AQL; `LibStub("AbsoluteQuestLog-1.0", true)` — retrieved by every sub-module |
| **CallbackHandler-1.0** | `LibStub("CallbackHandler-1.0"):New(AQL)` on line 10 of `AbsoluteQuestLog.lua` — provides `AQL.callbacks`, `AQL:RegisterCallback()`, and `AQL:UnregisterCallback()` |

All other Ace3 libraries (AceEvent, AceAddon, AceDB, AceConfig, AceConsole, AceHook, AceTimer, AceSerializer, AceGUI) are unused. WoW events are handled via a native `CreateFrame("Frame")` with `RegisterEvent`/`SetScript`. No Ace3 features beyond the above two are required.

---

## Design

### Files Created

```
Libs\
  LibStub\
    LibStub.lua
  CallbackHandler-1.0\
    CallbackHandler-1.0.lua
```

Both files are copied verbatim from the Questie addon's bundled copies, which are confirmed present on this machine:

- `D:\Projects\Wow Addons\Questie\Libs\LibStub\LibStub.lua`
- `D:\Projects\Wow Addons\Questie\Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua`

No modifications to either file.

### Files Modified

**`AbsoluteQuestLog.toc`**

Remove `## Dependencies: Ace3`. Add `## X-Embeds` to document the bundled libraries (standard CurseForge packaging convention). Add the two lib files at the top of the load list, before all AQL source files. Both must precede `AbsoluteQuestLog.lua` because line 6 calls `LibStub:NewLibrary()` (requires LibStub) and line 10 calls `LibStub("CallbackHandler-1.0"):New(AQL)` (requires CallbackHandler).

```
## Interface: 20505
## Title: Lib: AbsoluteQuestLog
## Notes: A rich quest data library for WoW Burning Crusade Anniversary.
## Author: Thad Ryker
## Version: 2.1.1
## X-Category: Library
## X-Embeds: LibStub, CallbackHandler-1.0

Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
AbsoluteQuestLog.lua
Core\WowQuestAPI.lua
Core\EventEngine.lua
Core\QuestCache.lua
Core\HistoryCache.lua
Providers\Provider.lua
Providers\QuestieProvider.lua
Providers\QuestWeaverProvider.lua
Providers\NullProvider.lua
```

**`CLAUDE.md`** — Add version 2.1.1 entry; update the architecture section to document the bundled libs and the removal of the Ace3 dependency.

### No Source Code Changes

Zero changes to any `.lua` source file. AQL already calls `LibStub:NewLibrary()` and `LibStub("CallbackHandler-1.0")` — those calls work identically whether the libraries were loaded by Ace3 or by AQL's own `Libs\` folder.

### `.wowproj` File

The `AbsoluteQuestLog.wowproj` file is a stale WoW Addon Studio project file referencing files that no longer exist (`AbsoluteQuestLog.Options.lua`) and missing all Core/Providers files. It is not used for deployment or builds. No update required.

---

## Deduplication Behaviour

Both LibStub and CallbackHandler-1.0 are designed for bundling. LibStub is self-bootstrapping and version-aware: if any other addon has already loaded a newer version, the bundled copy silently becomes a no-op. CallbackHandler-1.0 is registered through LibStub and follows the same versioning guarantee.

- **SocialQuest users** (who have Ace3): AQL is a dependency of SocialQuest and loads first. The bundled LibStub and CallbackHandler-1.0 register. When Ace3 subsequently loads its copies (equal or newer), LibStub deduplicates automatically. No conflict, no duplication of state.
- **Users without Ace3**: the bundled copies are the only source. AQL works standalone.

---

## Version

Version 2.1.0 was the first AQL change on 2026-03-21 (minor increment, revision reset). This bundling work is an additional change on the same day, so the versioning rule calls for a revision increment only: **2.1.0 → 2.1.1**.

---

## Constraints

- Copy lib files verbatim — do not modify them.
- Both lib files must appear in the `.toc` before `AbsoluteQuestLog.lua` (see load order rationale above).
- `## Dependencies: Ace3` must be removed entirely — no longer needed.

---

## Out of Scope

- No changes to SocialQuest (its Ace3 dependency is unaffected).
- No refactoring of AQL source files.
- No changes to any Provider or Core module.
