# Bundle LibStub and CallbackHandler-1.0 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove AbsoluteQuestLog's dependency on the full Ace3 addon by bundling the only two libraries it actually uses (LibStub and CallbackHandler-1.0) directly inside the AQL folder.

**Architecture:** Create a `Libs\` folder containing verbatim copies of LibStub and CallbackHandler-1.0 sourced from the Questie addon on disk. Update `AbsoluteQuestLog.toc` to load them before AQL's own files and remove `## Dependencies: Ace3`. No source code changes — AQL already calls `LibStub:NewLibrary()` and `LibStub("CallbackHandler-1.0")` correctly; it just needs those libraries loaded first.

**Tech Stack:** Lua 5.1, WoW TBC Anniversary (Interface 20505), LibStub, CallbackHandler-1.0

**Verification note:** This addon has no automated test framework. Each task's verification step is an in-game smoke test: `/reload` in WoW and confirm no errors in BugSack/chat.

**Spec:** `docs/superpowers/specs/2026-03-21-bundle-libstub-callbackhandler-design.md`

---

## Files Modified

| File | Change |
|---|---|
| `Libs\LibStub\LibStub.lua` | Create — verbatim copy from Questie |
| `Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua` | Create — verbatim copy from Questie |
| `AbsoluteQuestLog.toc` | Remove `## Dependencies: Ace3`; add `## X-Embeds`; add two lib lines before `AbsoluteQuestLog.lua`; bump version to 2.1.1 |
| `CLAUDE.md` | Add version 2.1.1 history entry; note bundled libs in architecture section |

---

## Task 1: Copy the library files

**Files:**
- Create: `Libs\LibStub\LibStub.lua`
- Create: `Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua`

Source files are confirmed on disk at:
- `D:\Projects\Wow Addons\Questie\Libs\LibStub\LibStub.lua`
- `D:\Projects\Wow Addons\Questie\Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua`

- [ ] **Step 1: Create the Libs directory structure and copy LibStub**

```bash
mkdir -p "D:\Projects\Wow Addons\Absolute-Quest-Log\Libs\LibStub"
cp "D:\Projects\Wow Addons\Questie\Libs\LibStub\LibStub.lua" \
   "D:\Projects\Wow Addons\Absolute-Quest-Log\Libs\LibStub\LibStub.lua"
```

Verify: the file exists and is non-empty.

```bash
ls -la "D:\Projects\Wow Addons\Absolute-Quest-Log\Libs\LibStub\LibStub.lua"
```

Expected: file exists, size > 0.

- [ ] **Step 2: Copy CallbackHandler-1.0**

```bash
mkdir -p "D:\Projects\Wow Addons\Absolute-Quest-Log\Libs\CallbackHandler-1.0"
cp "D:\Projects\Wow Addons\Questie\Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua" \
   "D:\Projects\Wow Addons\Absolute-Quest-Log\Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua"
```

Verify: the file exists and is non-empty.

```bash
ls -la "D:\Projects\Wow Addons\Absolute-Quest-Log\Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua"
```

Expected: file exists, size > 0.

- [ ] **Step 3: Confirm files are verbatim copies**

```bash
diff "D:\Projects\Wow Addons\Questie\Libs\LibStub\LibStub.lua" \
     "D:\Projects\Wow Addons\Absolute-Quest-Log\Libs\LibStub\LibStub.lua"
diff "D:\Projects\Wow Addons\Questie\Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua" \
     "D:\Projects\Wow Addons\Absolute-Quest-Log\Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua"
```

Expected: no output (files are identical).

---

## Task 2: Update AbsoluteQuestLog.toc and CLAUDE.md

**Files:**
- Modify: `AbsoluteQuestLog.toc`
- Modify: `CLAUDE.md`

### Step 2a: Update AbsoluteQuestLog.toc

- [ ] **Step 1: Open `AbsoluteQuestLog.toc`. Confirm current content:**

```
## Interface: 20505
## Title: Lib: AbsoluteQuestLog
## Notes: A rich quest data library for WoW Burning Crusade Anniversary.
## Author: Thad Ryker
## Version: 2.1.0
## X-Category: Library
## Dependencies: Ace3

AbsoluteQuestLog.lua
Core\WowQuestAPI.lua
...
```

- [ ] **Step 2: Replace the entire toc with:**

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

Key changes:
- `## Version: 2.1.0` → `## Version: 2.1.1`
- `## Dependencies: Ace3` removed
- `## X-Embeds: LibStub, CallbackHandler-1.0` added
- Two `Libs\` lines added before `AbsoluteQuestLog.lua`

### Step 2b: Update CLAUDE.md

- [ ] **Step 3: Add version 2.1.1 entry to the Version History section of `CLAUDE.md` (above the 2.1.0 entry):**

```markdown
### Version 2.1.1 (March 2026)
- Bundled LibStub and CallbackHandler-1.0 inside `Libs\`. Removed `## Dependencies: Ace3` from the toc. AQL is now fully self-contained with zero external dependencies. Both libraries are self-versioning via LibStub and deduplicate safely if Ace3 or another addon loads the same or newer versions.
```

- [ ] **Step 4: Update the Architecture section of `CLAUDE.md`. Find the Entry Point description and add a note about bundled libs:**

Locate the line:
```
`AbsoluteQuestLog.lua` — Registers the library with LibStub (`"AbsoluteQuestLog-1.0"`, minor=1). Sets up CallbackHandler (`AQL.callbacks`).
```

Prepend a new `### Bundled Libraries` subsection before `### Entry Point`:

```markdown
### Bundled Libraries (`Libs\`)

| File | Purpose |
|---|---|
| `Libs\LibStub\LibStub.lua` | Library bootstrapper. Self-versioning — safe to bundle; deduplicates automatically if another addon loads a newer version. |
| `Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua` | Callback registration and firing. Registered through LibStub; same deduplication guarantee. |

AQL has no external addon dependencies. The `Libs\` copies are the sole requirement for standalone use.
```

### Step 2c: In-game verification

- [ ] **Step 5: `/reload` in WoW (or restart the client).**

Expected: No errors in BugSack or chat related to AQL, LibStub, or CallbackHandler. If SocialQuest is also loaded, it must also load cleanly with no errors.

- [ ] **Step 6: Confirm AQL is accessible from chat:**

Type in chat:
```
/run print(LibStub("AbsoluteQuestLog-1.0", true) ~= nil)
```

Expected output: `true`

- [ ] **Step 7: Confirm CallbackHandler is still wired up:**

```
/run local AQL = LibStub("AbsoluteQuestLog-1.0", true); print(AQL and AQL.callbacks ~= nil)
```

Expected output: `true`

### Step 2d: Commit

- [ ] **Step 8: Commit all changes:**

```bash
git add Libs/LibStub/LibStub.lua \
        Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua \
        AbsoluteQuestLog.toc \
        CLAUDE.md
git commit -m "feat: bundle LibStub and CallbackHandler-1.0, remove Ace3 dependency (v2.1.1)"
```
