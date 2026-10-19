-- End-to-end regression test for the schema-v2 dynamic core and UI.
-- Run from the addon directory: lua tests/test_dynamic.lua

unpack = table.unpack or unpack
tinsert = table.insert
strlower = string.lower
strtrim = function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
UISpecialFrames, SlashCmdList = {}, {}

local function fail(message)
    error(message, 2)
end

local function check(value, message)
    if not value then fail(message) end
    return value
end

local function equal(actual, expected, message)
    if actual ~= expected then
        fail(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
    end
end

local frames, methods = {}, {}
local function noop() end
local function object(kind, name, parent)
    local value = {
        kind = kind, frameName = name, parent = parent, scripts = {}, events = {},
        shown = true, enabled = true, points = {}, width = 100, height = 100,
    }
    setmetatable(value, { __index = methods })
    frames[#frames + 1] = value
    if name then _G[name] = value end
    return value
end

for _, name in ipairs({
    "SetTexCoord", "SetMovable", "SetClampedToScreen", "SetDrawEdge",
    "SetHideCountdownNumbers", "SetWordWrap", "SetAutoFocus", "SetFontObject",
    "SetTextInsets", "SetFontString", "SetCheckedTexture", "SetTextColor",
    "SetJustifyH", "SetFrameStrata", "SetFrameLevel", "SetToplevel",
    "RegisterForDrag", "RegisterForClicks", "SetHighlightTexture", "SetAtlas",
    "SetBlendMode", "SetDrawSwipe", "EnableMouseWheel", "SetOwner", "SetSpellByID",
    "SetItemByID", "AddLine", "SetAllPoints", "StartMoving", "StopMovingOrSizing",
    "ClearFocus",
}) do
    methods[name] = noop
end

function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetScale(scale) self.scale = scale end
function methods:GetEffectiveScale() return self.scale or 1 end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:GetCenter() return self.centerX or 0, self.centerY or 0 end
function methods:SetPoint(...)
    local point = { ... }
    self.points[#self.points + 1] = point
    self.point = self.points[1]
end
function methods:GetPoint(index) return unpack(self.points[index or 1] or {}) end
function methods:GetNumPoints() return #self.points end
function methods:ClearAllPoints() self.points, self.point = {}, nil end
function methods:SetText(value) self.textValue = value end
function methods:GetText() return self.textValue or "" end
function methods:SetTexture(value) self.texture = value end
function methods:SetColorTexture(...) self.color = { ... } end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetColorRGB(r, g, b) self.pickerR, self.pickerG, self.pickerB = r, g, b end
function methods:GetColorRGB() return self.pickerR or 1, self.pickerG or 1, self.pickerB or 1 end
function methods:GetColorAlpha() return self.pickerAlpha or 1 end
function methods:SetupColorPickerAndShow(info)
    self.pickerInfo, self.pickerAlpha = info, info.opacity
    self:SetColorRGB(info.r, info.g, info.b)
    self:Show()
end
function methods:SetDesaturated(value) self.desaturated = value end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetChecked(value) self.checked = value and true or false end
function methods:GetChecked() return self.checked end
function methods:SetEnabled(value) self.enabled = value and true or false end
function methods:Enable() self:SetEnabled(true) end
function methods:Disable() self:SetEnabled(false) end
function methods:EnableMouse(value) self.mouse = value and true or false end
function methods:GetParent() return self.parent end
function methods:GetName() return self.frameName end
function methods:IsObjectType(kind) return self.kind == kind end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:GetScript(name) return self.scripts[name] end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:RegisterUnitEvent(event) self.events[event] = true end
function methods:CreateTexture() return object("Texture", nil, self) end
function methods:CreateFontString() return object("FontString", nil, self) end
function methods:SetScrollChild(child) self.scrollChild = child end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:GetVerticalScrollRange() return self.verticalScrollRange or 0 end
function methods:IsShown() return self.shown end
function methods:Show()
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide() self.shown = false end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:SetCooldown(start, duration, rate)
    self.cooldownKind, self.cdStart, self.cdDur, self.cdRate = "raw", start, duration, rate
end
function methods:SetCooldownFromDurationObject(duration)
    self.cooldownKind, self.durationObject = "object", duration
end
function methods:SetFont(path, size, flags)
    self.fontPath, self.fontSize, self.fontFlags = path, size, flags
    return true
end
function methods:GetCountdownFontString()
    if not self.countdownFontString then self.countdownFontString = object("FontString", nil, self) end
    return self.countdownFontString
end
function methods:SetCountdownFont(name) self.countdownFontName = name end
function methods:Clear()
    self.cooldownKind, self.cdStart, self.cdDur, self.durationObject = "clear", nil, nil, nil
end

CreateFrame = object
CreateFont = function(name) return object("Font", name) end
UIParent = object("Frame", "UIParent")
UIParent.width, UIParent.height = 1920, 1080
Minimap = object("Frame", "Minimap")
Minimap.width, Minimap.height = 140, 140
GameTooltip = object("Tooltip", "GameTooltip")
ColorPickerFrame = object("Frame", "ColorPickerFrame")
GetCursorPosition = function() return 0, 0 end
SetCursor, ResetCursor = noop, noop
local mouseFoci = {}
GetMouseFoci = function() return mouseFoci end
DoesAncestryIncludeAny = function(frame, foci)
    for _, focus in ipairs(foci or {}) do
        local current = focus
        while current do
            if current == frame then return true end
            current = current:GetParent()
        end
    end
    return false
end

local macroCalls = 0
local function macroTrap(name)
    return function()
        macroCalls = macroCalls + 1
        error(name .. " must not be called")
    end
end
for _, name in ipairs({ "GetMacroIndexByName", "GetMacroBody", "CreateMacro", "EditMacro", "DeleteMacro" }) do
    _G[name] = macroTrap(name)
end

local secretMarker = setmetatable({}, {
    __lt = function() error("secret value was ordered") end,
    __le = function() error("secret value was ordered") end,
    __sub = function() error("secret value was used in arithmetic") end,
    __add = function() error("secret value was used in arithmetic") end,
})
issecretvalue = function(value) return value == secretMarker end
issecrettable = function() return false end

local now = 100
GetTime = function() return now end
InCombatLockdown = function() return false end
UnitName = function() return "DynamicTester" end
UnitClass = function() return "Rogue" end
GetRealmName = function() return "TestRealm" end
local targetGUID = "Creature-Target-A"
UnitGUID = function(unit)
    if unit == "player" then return "Player-Dynamic-1" end
    if unit == "target" then return targetGUID end
end
UnitExists = function(unit) return unit == "target" and targetGUID ~= nil end
UnitCanAttack = function() return true end

C_Timer = { NewTicker = noop, After = function(_, callback) callback() end }
C_AddOns = { GetAddOnMetadata = function() return "test" end }
Enum = { SpellBookSpellBank = { Player = 0 }, ItemClass = { Projectile = 6 } }
local spellbookIDs = { 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 14251, 8676, 2003, 2004 }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #spellbookIDs, name = "General" } end,
    GetSpellBookItemInfo = function(index)
        local spellID = spellbookIDs[index]
        return { spellID = spellID, name = "Spell " .. spellID, isPassive = false, isOffSpec = false }
    end,
}

local RIPOSTE, SURPRISE = 14251, 8676
local AURA, DEBUFF, HYBRID, SECRET_CD, SECRET_AURA = 2001, 2002, 2003, 2004, 2005
local names = {
    [RIPOSTE] = "Riposte", [SURPRISE] = "Surprise Attack",
    [AURA] = "Test Aura", [DEBUFF] = "Test Debuff",
    [HYBRID] = "Ghostly Strike", [SECRET_CD] = "Secret Cooldown", [SECRET_AURA] = "Secret Aura",
}
for id = 101, 110 do names[id] = "Spell " .. id end
local cooldowns = {}
local secretDurationObject = { opaque = true }
C_Spell = {
    GetSpellName = function(id) return names[id] or ("Spell " .. tostring(id)) end,
    GetSpellTexture = function(id) return id end,
    GetSpellIDForSpellIdentifier = function(value)
        for id, name in pairs(names) do if name == value then return id end end
    end,
    GetSpellInfo = function() return nil end,
    GetSpellCooldown = function(id)
        if id == SECRET_CD then
            return { startTime = secretMarker, duration = secretMarker, isEnabled = secretMarker, modRate = secretMarker }
        end
        local value = cooldowns[id]
        if value then return { startTime = value[1], duration = value[2], isEnabled = value[3] } end
        return { startTime = 0, duration = 0, isEnabled = true }
    end,
    GetSpellCooldownDuration = function(id)
        if id == SECRET_CD then return secretDurationObject end
    end,
    GetSpellCharges = function() return nil end,
}

local itemNames = { [9001] = "Test Trinket" }
C_Item = {
    GetItemNameByID = function(id) return itemNames[id] end,
    GetItemIconByID = function(id) return id end,
    GetItemCount = function() return 1 end,
    GetItemInfoInstant = function(value)
        for id, name in pairs(itemNames) do if value == name then return id end end
    end,
    RequestLoadItemDataByID = noop,
}
C_Container = { GetItemCooldown = function() return 0, 0, 1 end, GetContainerNumSlots = function() return 0 end }
GetInventoryItemID = function() return nil end

local playerAuras, targetAuras = {}, {}
local unreadableAuras = {}
local auraDurationObject = { opaqueAura = true }
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        if unreadableAuras[id] then error("aura is restricted") end
        return playerAuras[id]
    end,
    GetAuraDataByIndex = function(unit, index, filter)
        equal(unit, "target", "debuff lookup unit")
        equal(filter, "HARMFUL|PLAYER", "debuff lookup filter")
        if unreadableAuras[DEBUFF] then error("debuff is restricted") end
        return targetAuras[index]
    end,
    GetAuraDuration = function() return auraDurationObject end,
}

local legacy = { cds = { 101 }, buffs = { AURA }, locked = false, custom = "obsolete" }
ForeverCDMAdvancedDB = legacy
assert(loadfile("ForeverCDMAdvanced.lua"))("ForeverCDMAdvanced")
assert(loadfile("ForeverCDMAdvanced_UI.lua"))("ForeverCDMAdvanced")

local function fire(event, ...)
    local pending = {}
    for _, frame in ipairs(frames) do
        if frame.events[event] then pending[#pending + 1] = frame end
    end
    for _, frame in ipairs(pending) do
        check(frame.scripts.OnEvent, "registered event " .. event .. " has no handler")
        frame.scripts.OnEvent(frame, event, ...)
    end
end

fire("PLAYER_LOGIN")
local API, db = ForeverCDMAdvanced, ForeverCDMAdvancedDB
for _, frame in ipairs(frames) do
    check(not frame.events.COMBAT_LOG_EVENT_UNFILTERED, "forbidden combat-log event was registered")
end
check(db ~= legacy, "legacy DB without schemaVersion was not replaced")
equal(db.schemaVersion, 2, "schema version")
check(type(db.settings) == "table", "db.settings was not created")
check(type(API.GetActiveProfile()) == "table", "active profile missing")
equal(#API.GetBars(), 0, "fresh active profile must have zero bars")
equal(macroCalls, 0, "migration touched macro APIs")
check(db.cds == nil and db.buffs == nil and db.locked == nil, "legacy static keys leaked into schema v2")

-- UI must build and toggle while the active profile has no bars.
check(type(ForeverCDMAdvanced_ToggleConfig) == "function", "UI toggle API missing")
check(type(API.CreateBar) == "function", "CreateBar API missing")
ForeverCDMAdvanced_ToggleConfig()
check(ForeverCDMAdvancedConfig and ForeverCDMAdvancedConfig:IsShown(), "zero-bar config did not open")
local newBarBox = check(_G.ForeverCDMAdvancedNewBarName, "Create Bar edit box missing")
local createButton
for _, frame in ipairs(frames) do
    if frame.kind == "Button" and frame.label and frame.label.textValue == "Create Bar" then createButton = frame break end
end
check(createButton and createButton.scripts.OnClick, "Create Bar button pathway missing")
newBarBox:SetText("From UI")
createButton.scripts.OnClick(createButton)
equal(#API.GetBars(), 1, "Create Bar UI pathway did not create a bar")
local uiBar = API.GetBars()[1]
equal(uiBar.pos[1], "CENTER", "new bar anchor point")
equal(uiBar.pos[2], 0, "new bar center x")
equal(uiBar.pos[3], 0, "new bar center y")

local lockButton, dropZone, spellRow
for _, frame in ipairs(frames) do
    if frame.kind == "Button" and frame.textValue == "Unlock bars" then lockButton = frame end
    if frame.scripts.OnReceiveDrag then dropZone = frame end
    if frame.id == 101 and frame.add and frame.scripts.OnDragStart and frame.scripts.OnDragStop then spellRow = frame end
end
check(lockButton and lockButton.scripts.OnClick, "Unlock bars button missing")
lockButton.scripts.OnClick(lockButton)
check(not db.settings.locked, "Unlock bars did not update core setting")
equal(lockButton.textValue, "Lock bars", "Unlock bars label did not refresh")
check(API.GetBarFrame(uiBar.id):IsShown(), "unlocked empty bar handle was not shown")
lockButton.scripts.OnClick(lockButton)
check(db.settings.locked, "Lock bars did not restore core setting")

check(dropZone and spellRow, "Spellbook drag/drop controls missing")
mouseFoci = { dropZone }
spellRow.scripts.OnDragStart(spellRow)
spellRow.scripts.OnDragStop(spellRow)
mouseFoci = {}
equal(#uiBar.entries, 1, "Spellbook drag did not add the spell")
equal(uiBar.entries[1].spellID, 101, "Spellbook drag added the wrong spell")
check(API.GetBarFrame(uiBar.id):IsShown(), "ready cooldown did not show its locked bar")

check(API.DeleteBar(uiBar.id), "could not clean up UI-created bar")
ForeverCDMAdvanced_ToggleConfig()
check(not ForeverCDMAdvancedConfig:IsShown(), "config did not toggle closed")

-- Dynamic bars, capacity, combination, grid validation and row-first layout.
local barID = API.CreateBar("Grid")
local bar = API.GetBar(barID)
equal(bar.rows, 1, "default rows")
equal(bar.columns, 4, "default columns")
equal(bar.borderMode, "eui", "default border mode")
equal(bar.borderSource, "MainBar", "default EUI border source")
check(bar.procGlowEnabled, "proc glow should default on")
equal(bar.procGlowSize, 8, "default proc glow size")
equal(bar.fontFace, "ellesmere", "default font face")
equal(bar.fontSize, 14, "default font size")
check(API.GetActiveProfile().bars == API.GetBars(), "bars are not profile-owned")
for id = 101, 104 do check(API.AddEntry(barID, id), "failed to add entry " .. id) end
local ok, reason = API.AddEntry(barID, 105)
check(not ok and reason:find("capacity", 1, true), "hard capacity did not reject fifth visual slot")
ok, reason = API.AddEntry(barID, 104)
check(not ok and reason:find("duplicate", 1, true), "duplicate spell was accepted")
check(API.SetBarOption(barID, "rows", 2), "could not set two rows")
check(API.SetBarOption(barID, "columns", 2), "could not set two columns")

local function pointOf(index)
    local frame = check(API.GetEntryFrame(barID, index), "missing entry frame " .. index)
    local point, relative, relativePoint, x, y = frame:GetPoint()
    return point, relative, relativePoint, x, y
end

local expected = { { 0, 0 }, { 40, 0 }, { 0, -40 }, { 40, -40 } }
for index = 1, 4 do
    local point, relative, relativePoint, x, y = pointOf(index)
    equal(point, "TOPLEFT", "RIGHT/DOWN anchor for entry " .. index)
    check(relative == API.GetBarFrame(barID), "entry anchor does not target its bar")
    equal(relativePoint, "TOPLEFT", "RIGHT/DOWN relative anchor")
    equal(x, expected[index][1], "row-first x for entry " .. index)
    equal(y, expected[index][2], "row-first y for entry " .. index)
end
local firstGridFrame = API.GetEntryFrame(barID, 1)
check(firstGridFrame.borderLines[1]:IsShown(), "EUI-unavailable fallback border was not shown")
equal(firstGridFrame.borderLines[1].color[1], 0, "fallback border red")
equal(firstGridFrame.count.fontSize, 14, "count font default size")
equal(firstGridFrame.cd.countdownFontString.fontSize, 14, "countdown font default size")

local borderColor = { r = 0.2, g = 0.3, b = 0.4, a = 0.9 }
check(API.SetBarOption(barID, "borderMode", "solid"), "solid border mode rejected")
check(API.SetBarOption(barID, "borderColor", borderColor), "border color rejected")
check(API.SetBarOption(barID, "borderSize", 3), "border size rejected")
borderColor.r = 0.9
equal(bar.borderColor.r, 0.2, "bar retained caller-owned border color table")
equal(firstGridFrame.borderLines[1].height, 3, "solid border size was not applied")
equal(firstGridFrame.borderLines[1].color[2], 0.3, "solid border color was not applied")
check(API.SetBarOption(barID, "fontFace", "arial"), "font face rejected")
check(API.SetBarOption(barID, "fontSize", 18), "font size rejected")
check(API.SetBarOption(barID, "fontOutline", "THICKOUTLINE"), "font outline rejected")
equal(firstGridFrame.count.fontPath, [[Fonts\ARIALN.TTF]], "count font face was not applied")
equal(firstGridFrame.count.fontSize, 18, "count font size was not applied")
equal(firstGridFrame.cd.countdownFontString.fontFlags, "THICKOUTLINE", "countdown outline was not applied")

local euiBorderCalls = {}
EllesmereUI = {
    _ModuleNS = {
        EllesmereUIActionBars = {
            EAB = { db = { profile = { bars = { MainBar = {
                borderTexture = "soft", borderSize = 2,
                borderColor = { r = 0.1, g = 0.6, b = 0.9, a = 0.8 },
                borderThickness = "medium",
            } } } } },
            ResolveBorderThickness = function() return 2 end,
        },
    },
    ApplyBorderStyle = function(...) euiBorderCalls[#euiBorderCalls + 1] = { ... } return true end,
    BorderPx = function() return 2 end,
    GetFontPath = function() return [[Fonts\EUI.ttf]] end,
}
check(API.SetBarOption(barID, "borderMode", "eui"), "EUI border mode rejected")
check(API.SetBarOption(barID, "fontFace", "ellesmere"), "EUI font rejected")
check(#euiBorderCalls > 0, "EUI textured border renderer was not called")
local latestEUI = euiBorderCalls[#euiBorderCalls]
equal(latestEUI[7], "soft", "wrong EUI border texture forwarded")
equal(firstGridFrame.count.fontPath, [[Fonts\EUI.ttf]], "EUI action-bar font was not applied")

ForeverCDMAdvanced_ToggleConfig()
local appearanceButton, glowSwatch, appearanceTitle
for _, frame in ipairs(frames) do
    if frame.kind == "Button" and frame.label and frame.label.textValue == "Appearance..." then appearanceButton = frame end
    if frame.kind == "Button" and frame.caption and frame.caption.textValue == "Glow color" then glowSwatch = frame end
    if frame.kind == "FontString" and type(frame.textValue) == "string" and frame.textValue:find("^APPEARANCE") then appearanceTitle = frame end
end
check(appearanceButton and appearanceButton.scripts.OnClick, "Appearance button missing")
appearanceButton.scripts.OnClick(appearanceButton)
check(appearanceTitle and appearanceTitle.textValue:find("Grid", 1, true), "Appearance panel did not select current bar")
check(glowSwatch and glowSwatch.scripts.OnClick, "Glow color swatch missing")
glowSwatch.scripts.OnClick(glowSwatch)
ColorPickerFrame:SetColorRGB(0.25, 0.5, 0.75)
ColorPickerFrame.pickerAlpha = 0.6
ColorPickerFrame.pickerInfo.swatchFunc()
equal(bar.procGlowColor.r, 0.25, "color picker did not update proc glow red")
equal(bar.procGlowColor.a, 0.6, "color picker did not update proc glow alpha")
ForeverCDMAdvanced_ToggleConfig()
check(API.SetBarOption(barID, "growX", "LEFT"), "LEFT growth rejected")
check(API.SetBarOption(barID, "growY", "UP"), "UP growth rejected")
expected = { { 0, 0 }, { -40, 0 }, { 0, 40 }, { -40, 40 } }
for index = 1, 4 do
    local point, _, relativePoint, x, y = pointOf(index)
    equal(point, "BOTTOMRIGHT", "LEFT/UP anchor for entry " .. index)
    equal(relativePoint, "BOTTOMRIGHT", "LEFT/UP relative anchor")
    equal(x, expected[index][1], "LEFT/UP row-first x for entry " .. index)
    equal(y, expected[index][2], "LEFT/UP row-first y for entry " .. index)
end
check(API.SetEntryCombined(barID, 2, true), "combine was rejected")
check(API.AddEntry(barID, 105), "combine did not release one visual slot")
local beforeMove = {}
for index, entry in ipairs(bar.entries) do beforeMove[index] = entry end
ok, reason = API.MoveEntry(barID, 2, -1)
check(not ok and reason:find("capacity", 1, true), "combined move was allowed to overflow capacity")
for index, entry in ipairs(beforeMove) do check(bar.entries[index] == entry, "rejected move changed entry order") end
check(bar.entries[2].combined, "rejected move lost combine state")
ok, reason = API.SetBarOption(barID, "rows", 1)
check(not ok and reason:find("smaller", 1, true), "grid shrink below visual slot count was accepted")

-- Modes validate strictly, and items can only use cooldown mode.
ok, reason = API.SetEntryOption(barID, 1, "mode", "invalid")
check(not ok and reason:find("invalid", 1, true), "invalid entry mode was accepted")
local itemBar = API.CreateBar("Items")
ok, reason = API.AddEntry(itemBar, "item:9001", "aura")
check(not ok and reason:find("only", 1, true), "item aura mode was accepted")
check(API.AddEntry(itemBar, "item:9001", "cooldown"), "item cooldown mode was rejected")
ok, reason = API.SetEntryOption(itemBar, 1, "mode", "debuff")
check(not ok and reason:find("only", 1, true), "existing item changed out of cooldown mode")

-- Profile copy owns a deep copy of the entire bar collection.
bar.pos = { "CENTER", 17, -23 }
bar.anchor = { frame = "UIParent", x = 4, y = 5 }
local originalProfileName = API.ActiveProfile()
local originalProfile = API.GetActiveProfile()
check(API.Profile("copy", "Copied"), "profile copy failed")
local copiedProfile = API.GetActiveProfile()
check(copiedProfile ~= originalProfile and copiedProfile.bars ~= originalProfile.bars, "profile bars table was shared")
check(copiedProfile.bars[1] ~= originalProfile.bars[1], "bar table was shared")
check(copiedProfile.bars[1].entries ~= originalProfile.bars[1].entries, "entry list was shared")
check(copiedProfile.bars[1].entries[1] ~= originalProfile.bars[1].entries[1], "entry table was shared")
check(copiedProfile.bars[1].pos ~= originalProfile.bars[1].pos, "bar position was shared")
check(copiedProfile.bars[1].anchor ~= originalProfile.bars[1].anchor, "bar anchor was shared")
copiedProfile.bars[1].name = "Copied Grid"
copiedProfile.bars[1].pos[2] = 999
copiedProfile.bars[1].anchor.x = 999
copiedProfile.bars[1].entries[1].duration = 77
copiedProfile.bars[1].borderColor.r = 0.99
copiedProfile.bars[1].procGlowColor.g = 0.01
equal(originalProfile.bars[1].name, "Grid", "copy mutation changed original bar")
equal(originalProfile.bars[1].pos[2], 17, "copy mutation changed original position")
equal(originalProfile.bars[1].anchor.x, 4, "copy mutation changed original anchor")
check(originalProfile.bars[1].entries[1].duration == nil, "copy mutation changed original entry")
equal(originalProfile.bars[1].borderColor.r, 0.2, "copy shared border color table")
equal(originalProfile.bars[1].procGlowColor.g, 0.5, "copy shared proc glow color table")
check(API.Profile("new", "Empty"), "new profile failed")
equal(#API.GetBars(), 0, "new profile was not empty")
check(API.Profile("use", originalProfileName), "profile use failed")
check(API.GetActiveProfile() == originalProfile, "profile use selected wrong profile")

-- Basic aura, debuff and auraCooldown paths, including a manual-duration estimate.
local stateBar = API.CreateBar("States")
check(API.SetBarOption(stateBar, "rows", 2), "state bar resize failed")
check(API.AddEntry(stateBar, AURA, "aura"), "aura entry failed")
check(API.AddEntry(stateBar, DEBUFF, "debuff"), "debuff entry failed")
check(API.AddEntry(stateBar, HYBRID, "auraCooldown"), "auraCooldown entry failed")
check(API.SetEntryOption(stateBar, 1, "duration", 12), "manual aura duration rejected")
playerAuras[AURA] = { auraInstanceID = 11, duration = 15, expirationTime = now + 15, applications = 2 }
targetAuras[1] = { spellId = DEBUFF, name = names[DEBUFF], auraInstanceID = 12, duration = 20, expirationTime = now + 20 }
API.Refresh()
local auraFrame, debuffFrame = API.GetEntryFrame(stateBar, 1), API.GetEntryFrame(stateBar, 2)
equal(auraFrame.cd.cdDur, 15, "aura duration was not drawn")
equal(auraFrame.count.textValue, 2, "aura applications were not drawn")
equal(debuffFrame.cd.cdDur, 20, "debuff duration was not drawn")
playerAuras[AURA] = nil
unreadableAuras[AURA] = true
fire("UNIT_AURA", "player", { isFullUpdate = true })
equal(auraFrame.alpha, 0.85, "restricted full aura update discarded a known active aura")
fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 11 } })
equal(auraFrame.alpha, 0.25, "removed aura instance remained cached as active")
unreadableAuras[AURA] = nil

-- A secret aura duration uses the widget and its completion clears the cached instance.
check(API.AddEntry(stateBar, SECRET_AURA, "aura"), "secret aura entry failed")
playerAuras[SECRET_AURA] = {
    auraInstanceID = 21, duration = secretMarker, expirationTime = secretMarker, applications = 0,
}
API.Refresh()
local secretAuraFrame = API.GetEntryFrame(stateBar, 4)
equal(secretAuraFrame.cd.cooldownKind, "object", "secret aura did not use duration object")
playerAuras[SECRET_AURA] = nil
unreadableAuras[SECRET_AURA] = true
secretAuraFrame.cd.scripts.OnCooldownDone(secretAuraFrame.cd)
equal(secretAuraFrame.alpha, 0.25, "secret aura completion left cached aura active")
unreadableAuras[SECRET_AURA] = nil
playerAuras[AURA] = { auraInstanceID = 13, duration = 15, expirationTime = now + 15, applications = 1 }
API.Refresh()
targetGUID = "Creature-Target-B"
unreadableAuras[DEBUFF] = true
API.Refresh()
equal(debuffFrame.alpha, 0.25, "cached debuff leaked to a different target")
unreadableAuras[DEBUFF] = nil
targetGUID = "Creature-Target-A"
targetAuras = {}
cooldowns[HYBRID] = { now - 1, 30, true }
API.Refresh()
local hybridFrame = API.GetEntryFrame(stateBar, 3)
equal(hybridFrame.cd.cdDur, 30, "auraCooldown did not fall back to spell cooldown")
playerAuras[AURA] = nil
unreadableAuras[AURA] = true
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-aura", AURA)
equal(auraFrame.cd.cdStart, now, "manual aura fallback did not start at cast time")
equal(auraFrame.cd.cdDur, 12, "manual aura fallback used wrong duration")
equal(auraFrame.alpha, 0.85, "manual aura fallback should be estimated")
unreadableAuras[AURA] = nil

-- Secret cooldown fields must go only through the opaque duration-object API.
local secretBar = API.CreateBar("Secret")
check(API.AddEntry(secretBar, SECRET_CD, "cooldown"), "secret cooldown entry failed")
local secretFrame = API.GetEntryFrame(secretBar, 1)
equal(secretFrame.cd.cooldownKind, "object", "secret cooldown used raw SetCooldown")
check(secretFrame.cd.durationObject == secretDurationObject, "wrong spell duration object forwarded")

-- Reactive Riposte: proc, latch, duplicate suppression, retrigger and cooldown completion.
local reactiveBar = API.CreateBar("Reactive")
check(API.AddEntry(reactiveBar, RIPOSTE), "Riposte entry failed")
local riposte = API.GetEntryFrame(reactiveBar, 1)
equal(API.GetBar(reactiveBar).entries[1].mode, "reactive", "Riposte catalog mode")
check(not riposte:IsShown(), "locked inactive Riposte must be hidden")
fire("UNIT_COMBAT", "player", "PARRY", nil, 0, 0)
local activated, count = true, 1
check(riposte:IsShown(), "UNIT_COMBAT did not activate Riposte")
check(riposte:IsShown() and riposte.cd.cdStart == now and riposte.cd.cdDur == 4, "Riposte proc timer was not shown")
check(riposte.proc:IsShown(), "ready proc glow was not shown")
equal(riposte.proc.texture, [[Interface\SpellActivationOverlay\IconAlert]], "wrong proc glow texture")
equal(riposte.proc.vertexColor[1], 1, "ready proc glow red")
equal(riposte.proc.vertexColor[2], 0.82, "ready proc glow green")
equal(riposte.proc.points[1][4], -8, "proc glow size was not applied")
activated, count = API.ActivateReactive("riposte")
check(not activated and count == 0, "duplicate reactive trigger was not suppressed")

-- A confirmed cooldown during the proc uses Octo's red glow, not the old red fill.
cooldowns[RIPOSTE] = { now, 6, true }
API.Refresh()
check(riposte.proc:IsShown(), "blocked proc glow was not shown")
equal(riposte.proc.vertexColor[1], 1, "blocked proc glow red")
equal(riposte.proc.vertexColor[2], 0, "blocked proc glow should be red")
now = now + 0.1
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-riposte", RIPOSTE)
check(riposte:IsShown() and riposte.cd.cdDur == 6, "successful Riposte did not latch its cooldown")
check(not riposte.proc:IsShown(), "proc glow remained after successful use")
check(type(riposte.cd.scripts.OnCooldownDone) == "function", "cooldown frame lacks OnCooldownDone")

-- A new proc during the latched cooldown can be hidden; the independent tracker
-- must still complete and reveal the gold proc before its window expires.
now = now + 0.9
activated = API.ActivateReactive("riposte")
check(activated and riposte:IsShown() and riposte.proc:IsShown(), "proc during latched cooldown was not shown")
activated = API.ActivateReactive("riposte")
check(not activated, "duplicate proc during latched cooldown was not suppressed")
check(API.SetBarOption(reactiveBar, "procCooldownMode", "hide"), "hide proc mode rejected")
check(not riposte:IsShown(), "blocked proc was not hidden")
check(type(riposte.cdTracker.scripts.OnCooldownDone) == "function", "hidden cooldown tracker callback missing")
cooldowns[RIPOSTE] = nil
riposte.cdTracker.scripts.OnCooldownDone(riposte.cdTracker)
check(riposte:IsShown(), "tracker completion did not reveal active proc")
check(riposte.proc:IsShown(), "tracker completion did not restore proc glow")
equal(riposte.proc.vertexColor[2], 0.82, "tracker completion did not restore configured glow color")
now = now + 4.1
API.Refresh()
check(not riposte:IsShown(), "expired reactive proc did not hide")

-- Surprise procs are tied to the target that dodged.
local surpriseBar = API.CreateBar("Surprise")
check(API.AddEntry(surpriseBar, SURPRISE), "Surprise Attack entry failed")
local surprise = API.GetEntryFrame(surpriseBar, 1)
now = now + 1
fire("UNIT_COMBAT", "target", "DODGE", nil, 0, 0)
check(surprise:IsShown(), "Surprise proc hidden on matching target")
targetGUID = "Creature-Target-B"
API.Refresh()
check(not surprise:IsShown(), "Surprise proc followed a different target")

equal(macroCalls, 0, "runtime or UI touched macro APIs")
print("dynamic schema, bars, profiles, layout, state modes, reactive, secret cooldown and UI checks passed")
