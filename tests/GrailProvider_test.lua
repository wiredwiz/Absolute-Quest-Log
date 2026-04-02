-- tests/GrailProvider_test.lua
-- Run from repo root: lua tests/GrailProvider_test.lua
-- Tests GrailProvider variant chain logic with a mock Grail + AQL environment.

local failures = 0
local function check(label, cond)
    if not cond then
        print("FAIL: " .. label)
        failures = failures + 1
    else
        print("pass: " .. label)
    end
end

------------------------------------------------------------------------
-- Minimal WoW global stubs
------------------------------------------------------------------------
_G = _G or {}

-- LibStub mock: returns the AQL table when queried.
local aql = {
    ChainStatus = { Known="known", Unknown="unknown", NotAChain="not_a_chain" },
    StepStatus  = { Unknown="unknown", Active="active", Completed="completed",
                    Finished="finished", Failed="failed",
                    Available="available", Unavailable="unavailable" },
    Provider    = { Grail="Grail" },
    Capability  = { Chain="Chain", QuestInfo="QuestInfo", Requirements="Requirements" },
    HistoryCache = nil,
    QuestCache   = nil,
}
function LibStub(name, silent)
    if name == "AbsoluteQuestLog-1.0" then return aql end
    return nil
end
_G["LibStub"] = LibStub

------------------------------------------------------------------------
-- Mock Grail data:
--   3 variant roots (101, 102, 103) → "Beating Them Back!" in "Dun Morogh"
--   Each root → 1 step-2 variant (201/202/203 "Lions for Lambs" same zone)
--                + 1 letter-quest side branch (901/902/903 different name/zone)
--   All step-2 variants → 1 step-3 quest (301 "Join the Battle!" same zone)
--   Non-variant chain: 500 → 501 (simple 2-step, no variants)
------------------------------------------------------------------------
local questNames = {
    [101]="Beating Them Back!", [102]="Beating Them Back!", [103]="Beating Them Back!",
    [201]="Lions for Lambs",    [202]="Lions for Lambs",    [203]="Lions for Lambs",
    [301]="Join the Battle!",
    [901]="Simple Letter",      [902]="Glyphic Letter",     [903]="Embossed Letter",
    [500]="The First Step",
    [501]="The Second Step",
}
local questMapAreas = {
    [101]=1, [102]=1, [103]=1,
    [201]=1, [202]=1, [203]=1,
    [301]=1,
    [901]=2, [902]=2, [903]=2,  -- different zone → fail majority vote
    [500]=3, [501]=3,
}
local mapAreaNames = { [1]="Dun Morogh", [2]="Elwynn Forest", [3]="Westfall" }

_G["Grail"] = {
    -- questPrerequisites: keys = quests that HAVE prerequisites.
    -- Values are comma-separated prereq questIDs.
    questPrerequisites = {
        [201]="101", [202]="102", [203]="103",
        [301]="201,202,203",
        [901]="101", [902]="102", [903]="103",
        [501]="500",
    },
    questCodes = {},
    QuestName = function(self, id) return questNames[id] end,
    MapAreaName = function(self, mapArea) return mapAreaNames[mapArea] end,
    QuestLocationsAccept = function(self, id)
        local z = questMapAreas[id]
        if z then return {{ mapArea = z }} else return {} end
    end,
    QuestLevelRequired = function(self, id) return 1 end,
    QuestLevelVariableMax = nil,
}

------------------------------------------------------------------------
-- Load GrailProvider (sets aql.GrailProvider at the bottom of the file).
------------------------------------------------------------------------
dofile("Providers/GrailProvider.lua")
local GP = aql.GrailProvider

------------------------------------------------------------------------
-- Task 1 tests: variant group detection via GetChainInfo results.
-- After Task 1, these checks confirm the groups are built correctly
-- (same chainID returned for all variants of the same root group).
------------------------------------------------------------------------
local r101 = GP:GetChainInfo(101)
local r102 = GP:GetChainInfo(102)
local r103 = GP:GetChainInfo(103)

check("101 known",             r101.knownStatus == "known")
check("102 known",             r102.knownStatus == "known")
check("103 known",             r103.knownStatus == "known")
check("101 chainID is 101",    r101.chains and r101.chains[1].chainID == 101)
check("102 chainID is 101",    r102.chains and r102.chains[1].chainID == 101)
check("103 chainID is 101",    r103.chains and r103.chains[1].chainID == 101)

------------------------------------------------------------------------
-- Task 2 tests: buildVariantChain produces correct step count + structure.
------------------------------------------------------------------------
check("101 length=3",          r101.chains and r101.chains[1].length == 3)
check("102 length=3",          r102.chains and r102.chains[1].length == 3)
check("step1 is group",        r101.chains and r101.chains[1].steps[1].quests ~= nil)
check("step1 has 3 variants",  r101.chains and r101.chains[1].steps[1].quests ~= nil
                                and #r101.chains[1].steps[1].quests == 3)
check("step2 is group",        r101.chains and r101.chains[1].steps[2].quests ~= nil)
check("step2 has 3 variants",  r101.chains and #r101.chains[1].steps[2].quests == 3)
check("step3 is single quest", r101.chains and r101.chains[1].steps[3].questID ~= nil)
check("step3 questID is 301",  r101.chains and r101.chains[1].steps[3].questID == 301)

-- Majority-vote filter: side branch letter quests must NOT appear in step2.
if r101.chains and r101.chains[1].steps[2].quests then
    local step2IDs = {}
    for _, sq in ipairs(r101.chains[1].steps[2].quests) do
        step2IDs[sq.questID] = true
    end
    check("901 not in step2 (majority vote)", not step2IDs[901])
    check("902 not in step2 (majority vote)", not step2IDs[902])
    check("903 not in step2 (majority vote)", not step2IDs[903])
    check("201 in step2",                     step2IDs[201])
    check("202 in step2",                     step2IDs[202])
    check("203 in step2",                     step2IDs[203])
else
    check("step2 quests accessible", false)
end

------------------------------------------------------------------------
-- Task 3 tests: GetChainInfo step detection for mid-chain + convergence.
------------------------------------------------------------------------
local r201 = GP:GetChainInfo(201)
local r301 = GP:GetChainInfo(301)
local r901 = GP:GetChainInfo(901)

check("201 known",             r201.knownStatus == "known")
check("201 chainID is 101",    r201.chains and r201.chains[1].chainID == 101)
check("201 step is 2",         r201.chains and r201.chains[1].step == 2)
check("301 known",             r301.knownStatus == "known")
check("301 chainID is 101",    r301.chains and r301.chains[1].chainID == 101)
check("301 step is 3",         r301.chains and r301.chains[1].step == 3)
check("901 not a chain",       r901.knownStatus == "not_a_chain")

-- Non-variant chain: 500 → 501 (no variants; falls through to buildChainFromRoot).
local r500 = GP:GetChainInfo(500)
local r501 = GP:GetChainInfo(501)
check("500 known",             r500.knownStatus == "known")
check("500 chainID is 500",    r500.chains and r500.chains[1].chainID == 500)
check("500 step is 1",         r500.chains and r500.chains[1].step == 1)
check("500 length is 2",       r500.chains and r500.chains[1].length == 2)
check("501 known",             r501.knownStatus == "known")
check("501 chainID is 500",    r501.chains and r501.chains[1].chainID == 500)
check("501 step is 2",         r501.chains and r501.chains[1].step == 2)

------------------------------------------------------------------------
print(string.rep("-", 50))
if failures == 0 then
    print("All tests passed.")
else
    print(failures .. " test(s) FAILED.")
    os.exit(1)
end
