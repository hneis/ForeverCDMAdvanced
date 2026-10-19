-- ForeverCDMAdvanced.lua - dynamic, secret-safe cooldown and aura bars
-- Interface: 16001; Lua 5.1

local ADDON = ...
local TITLE = "|cffd2621fForever CDM Advanced|r"
local SCHEMA = 2
local MODES = { cooldown=true, aura=true, debuff=true, auraCooldown=true, reactive=true }
local READY = { always=true, combat=true, hide=true }
local INACTIVE = { show=true, hide=true }
local GROW_X = { RIGHT=true, LEFT=true }
local GROW_Y = { DOWN=true, UP=true }
local PROC_CD = { red=true, hide=true }
local BORDER_MODES = { eui=true, solid=true, none=true }
local BORDER_SOURCES = { MainBar=true, Bar2=true, Bar3=true, Bar4=true, Bar5=true, Bar6=true,
    Bar7=true, Bar8=true, Bar9=true, Bar10=true }
local FONT_FACES = { ellesmere=true, friz=true, arial=true, skurri=true, morpheus=true }
local FONT_OUTLINES = { NONE=true, OUTLINE=true, THICKOUTLINE=true }
local DEFAULT_BORDER_COLOR = {r=0, g=0, b=0, a=1}
local DEFAULT_PROC_COLOR = {r=1, g=0.82, b=0.1, a=1}

local db, profile
local rows, icons, entryRuntime = {}, {}, {}
local runtimeGeneration = 1
local cooldownDriver
local ranks, siblings, knownSpells, knownNames = {}, {}, {}, {}
local spellbookScanned = false
local editModeActive, inCombat, itemNamesPending = false, false, false
local refreshAll

local function secret(v) return issecretvalue and issecretvalue(v) end
local function secretTable(v) return issecrettable and issecrettable(v) end
local function say(fmt, ...)
    print(TITLE .. ": " .. string.format(fmt, ...))
end
local function configChanged()
    if ForeverCDMAdvanced_RefreshConfig then ForeverCDMAdvanced_RefreshConfig() end
end
local function changed()
    refreshAll()
    configChanged()
end
local function trim(s)
    if strtrim then return strtrim(s or "") end
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function validColor(value)
    if type(value) ~= "table" or secret(value) or secretTable(value) then return nil end
    local out = {}
    for _, key in ipairs({"r", "g", "b", "a"}) do
        local component = value[key]
        if secret(component) or type(component) ~= "number" or component ~= component or component < 0 or component > 1 then return nil end
        out[key] = component
    end
    return out
end

local function normalizeColor(value, fallback)
    return validColor(value) or {r=fallback.r, g=fallback.g, b=fallback.b, a=fallback.a}
end

local function normalizeNumber(value, fallback, minimum, maximum)
    if secret(value) then return fallback end
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function enumOr(values, value, fallback)
    return not secret(value) and values[value] and value or fallback
end

-- Database and profiles -------------------------------------------------------

local function playerGUID()
    local g = UnitGUID and UnitGUID("player")
    if type(g) == "string" and not secret(g) and g ~= "" then return g end
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if secret(name) then name = "?" end
    if secret(realm) then realm = "?" end
    return tostring(name or "?") .. " - " .. tostring(realm or "?")
end

local function characterLabel()
    local name = UnitName and UnitName("player")
    if secret(name) then name = "?" end
    name = tostring(name or "?")
    local class = UnitClass and UnitClass("player")
    if type(class) == "string" and not secret(class) and class ~= "" then name = name .. " (" .. class .. ")" end
    local realm = GetRealmName and GetRealmName()
    if secret(realm) then realm = "?" end
    return name .. " - " .. tostring(realm or "?")
end

local function freshDB()
    return {
        schemaVersion=SCHEMA,
        settings={locked=true, fade=nil, showNames=false, minimap={angle=215, hide=false}},
        profiles={}, profileKeys={}, charLabels={},
    }
end

local function freshProfile()
    return { bars={}, nextBarID=1, nextEntryID=1 }
end

local function normalizeProfile(saved)
    if type(saved) ~= "table" or secret(saved) or secretTable(saved) then saved = freshProfile() end
    saved.bars = type(saved.bars) == "table" and saved.bars or {}
    local usedBars, usedEntries, maxBar, maxEntry = {}, {}, 0, 0
    for index, bar in ipairs(saved.bars) do
        if type(bar) ~= "table" then bar = {} saved.bars[index] = bar end
        local id = tonumber(bar.id)
        if not id or id < 1 or id ~= math.floor(id) or usedBars[id] then
            id = maxBar + 1
            while usedBars[id] do id = id + 1 end
        end
        bar.id, usedBars[id], maxBar = id, true, math.max(maxBar, id)
        bar.name = type(bar.name) == "string" and bar.name ~= "" and bar.name or ("Bar " .. id)
        bar.rows = math.max(1, math.min(20, math.floor(tonumber(bar.rows) or 1)))
        bar.columns = math.max(1, math.min(20, math.floor(tonumber(bar.columns) or 4)))
        bar.size = math.max(12, math.min(96, tonumber(bar.size) or 36))
        bar.spacing = math.max(0, math.min(30, tonumber(bar.spacing) or 4))
        bar.growX = GROW_X[bar.growX] and bar.growX or "RIGHT"
        bar.growY = GROW_Y[bar.growY] and bar.growY or "DOWN"
        bar.procCooldownMode = PROC_CD[bar.procCooldownMode] and bar.procCooldownMode or "red"
        bar.borderMode = enumOr(BORDER_MODES, bar.borderMode, "eui")
        bar.borderSource = enumOr(BORDER_SOURCES, bar.borderSource, "MainBar")
        bar.borderColor = normalizeColor(bar.borderColor, DEFAULT_BORDER_COLOR)
        bar.borderSize = normalizeNumber(bar.borderSize, 1, 0, 8)
        if secret(bar.procGlowEnabled) or type(bar.procGlowEnabled) ~= "boolean" then bar.procGlowEnabled = true end
        bar.procGlowColor = normalizeColor(bar.procGlowColor, DEFAULT_PROC_COLOR)
        bar.procGlowSize = normalizeNumber(bar.procGlowSize, 8, 0, 20)
        bar.fontFace = enumOr(FONT_FACES, bar.fontFace, "ellesmere")
        bar.fontSize = normalizeNumber(bar.fontSize, 14, 6, 64)
        bar.fontOutline = enumOr(FONT_OUTLINES, bar.fontOutline, "OUTLINE")
        local validPoints = {CENTER=true, TOP=true, BOTTOM=true, LEFT=true, RIGHT=true,
            TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true}
        bar.pos = type(bar.pos) == "table" and bar.pos or {"CENTER", 0, -170 + (index - 1) * 54}
        bar.pos = {validPoints[bar.pos[1]] and bar.pos[1] or "CENTER", tonumber(bar.pos[2]) or 0, tonumber(bar.pos[3]) or 0}
        if type(bar.anchor) == "table" then
            bar.anchor.x, bar.anchor.y = tonumber(bar.anchor.x) or 0, tonumber(bar.anchor.y) or 0
        end
        bar.entries = type(bar.entries) == "table" and bar.entries or {}
        for entryIndex, entry in ipairs(bar.entries) do
            if type(entry) ~= "table" then entry = {} bar.entries[entryIndex] = entry end
            local uid = tonumber(entry.uid)
            if not uid or uid < 1 or uid ~= math.floor(uid) or usedEntries[uid] then
                uid = maxEntry + 1
                while usedEntries[uid] do uid = uid + 1 end
            end
            entry.uid, usedEntries[uid], maxEntry = uid, true, math.max(maxEntry, uid)
            entry.spellID = tonumber(entry.spellID) or 0
            entry.mode = MODES[entry.mode] and entry.mode or "cooldown"
            if entry.spellID < 0 then entry.mode = "cooldown" end
            entry.readyVisibility = READY[entry.readyVisibility] and entry.readyVisibility or "always"
            entry.inactiveVisibility = INACTIVE[entry.inactiveVisibility] and entry.inactiveVisibility or "show"
            entry.combined = entryIndex > 1 and entry.combined and true or false
        end
        local slots = 0
        for entryIndex, entry in ipairs(bar.entries) do if entryIndex == 1 or not entry.combined then slots = slots + 1 end end
        if slots > bar.rows * bar.columns then
            bar.columns = math.min(20, math.max(bar.columns, math.ceil(slots / 20)))
            bar.rows = math.min(20, math.max(bar.rows, math.ceil(slots / bar.columns)))
        end
    end
    saved.nextBarID = math.max(maxBar + 1, tonumber(saved.nextBarID) or 1)
    saved.nextEntryID = math.max(maxEntry + 1, tonumber(saved.nextEntryID) or 1)
    return saved
end

local function uniqueProfileName(base, exceptGUID)
    local name, n = base, 1
    while db.profiles[name] do
        n = n + 1
        name = base .. " " .. n
    end
    return name
end

local function selectCharacterProfile()
    local guid, label = playerGUID(), characterLabel()
    db.charLabels[guid] = label
    local name = db.profileKeys[guid]
    if not name or not db.profiles[name] then
        name = uniqueProfileName(label, guid)
        db.profiles[name] = db.profiles[name] or freshProfile()
        db.profileKeys[guid] = name
    end
    profile = normalizeProfile(db.profiles[name])
    db.profiles[name] = profile
end

local function ensureDB()
    if type(ForeverCDMAdvancedDB) ~= "table" or ForeverCDMAdvancedDB.schemaVersion ~= SCHEMA then
        ForeverCDMAdvancedDB = freshDB()
    end
    db = ForeverCDMAdvancedDB
    db.profiles = type(db.profiles) == "table" and db.profiles or {}
    db.profileKeys = type(db.profileKeys) == "table" and db.profileKeys or {}
    db.charLabels = type(db.charLabels) == "table" and db.charLabels or {}
    db.settings = type(db.settings) == "table" and db.settings or {}
    if db.settings.locked == nil then db.settings.locked = true end
    if db.settings.showNames == nil then db.settings.showNames = false end
    db.settings.minimap = type(db.settings.minimap) == "table" and db.settings.minimap or {angle=215, hide=false}
    db.locked, db.fade, db.showNames, db.minimap = nil, nil, nil, nil
    selectCharacterProfile()
end

local function cloneEntry(e)
    local out = {}
    for k, v in pairs(e) do out[k] = v end
    return out
end

local function cloneProfile(p)
    local out = freshProfile()
    out.nextBarID, out.nextEntryID = p.nextBarID or 1, p.nextEntryID or 1
    for _, bar in ipairs(p.bars or {}) do
        local b = {}
        for k, v in pairs(bar) do
            if k ~= "entries" and k ~= "pos" and k ~= "anchor" and k ~= "borderColor" and k ~= "procGlowColor" then b[k] = v end
        end
        b.borderColor = normalizeColor(bar.borderColor, DEFAULT_BORDER_COLOR)
        b.procGlowColor = normalizeColor(bar.procGlowColor, DEFAULT_PROC_COLOR)
        b.pos = {unpack(bar.pos or {"CENTER", 0, 0})}
        if type(bar.anchor) == "table" then
            b.anchor = {}
            for k, v in pairs(bar.anchor) do b.anchor[k] = v end
        end
        b.entries = {}
        for _, e in ipairs(bar.entries or {}) do b.entries[#b.entries + 1] = cloneEntry(e) end
        out.bars[#out.bars + 1] = b
    end
    return out
end

local function activeProfileName() return db and db.profileKeys[playerGUID()] end

-- Spell helpers ---------------------------------------------------------------

local function resolveSpell(value)
    if type(value) == "number" then return value ~= 0 and value or nil end
    value = trim(value)
    if value == "" then return nil end
    local item = value:match("item:(%d+)")
    if item then return -tonumber(item) end
    local id = tonumber(value)
    if id then return id ~= 0 and id or nil end
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local ok, found = pcall(C_Spell.GetSpellIDForSpellIdentifier, value)
        if ok and type(found) == "number" and not secret(found) then return found end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, value)
        if ok and type(info) == "table" and type(info.spellID) == "number" and not secret(info.spellID) then return info.spellID end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, found = pcall(C_Item.GetItemInfoInstant, value)
        if ok and type(found) == "number" and not secret(found) then return -found end
    end
end

local function spellName(id)
    if type(id) ~= "number" then return "?" end
    if id < 0 then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(-id)
        if secret(name) then name = nil end
        if not name then
            itemNamesPending = true
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(-id) end
        end
        return name or ("item " .. tostring(-id))
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return (type(name) == "string" and not secret(name) and name) or ("spell " .. tostring(id))
end

local function spellIcon(id)
    if type(id) ~= "number" then return 134400 end
    local icon
    if id < 0 then icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(-id)
    else icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) end
    return (not secret(icon) and icon) or 134400
end

local function buildRankIndex()
    ranks, siblings, knownSpells, knownNames = {}, {}, {}, {}
    spellbookScanned = false
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local byName = {}
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if not secret(info) and not secretTable(info) and type(info) == "table" then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                if not secret(item) and not secretTable(item) and type(item) == "table" then
                    local spellID = item.spellID
                    if not secret(spellID) and type(spellID) == "number" then
                    spellbookScanned = true
                    local passive = secret(item.isPassive) and true or item.isPassive
                    local offSpec = secret(item.isOffSpec) and true or item.isOffSpec
                    if not passive and not offSpec then knownSpells[spellID] = true end
                    local sub = item.subName
                    if secret(sub) then sub = nil end
                    if (not sub or sub == "") and C_Spell and C_Spell.GetSpellSubtext then sub = C_Spell.GetSpellSubtext(spellID) end
                    if type(sub) == "string" and not secret(sub) and sub ~= "" then ranks[spellID] = sub end
                    local name = type(item.name) == "string" and not secret(item.name) and item.name or spellName(spellID)
                    if not passive and not offSpec then knownNames[name] = true end
                    byName[name] = byName[name] or {}
                    byName[name][#byName[name] + 1] = spellID
                    end
                end
            end
        end
    end
    for _, list in pairs(byName) do
        if #list > 1 then for _, id in ipairs(list) do siblings[id] = list end end
    end
end

local function rankNumber(id) return tonumber((ranks[id] or ""):match("%d+")) or 0 end

local function entryAvailable(entry)
    if entry.spellID < 0 or not spellbookScanned then return true end
    if entry.mode == "aura" or entry.mode == "debuff" then return true end
    if knownSpells[entry.spellID] or knownNames[spellName(entry.spellID)] then return true end
    for _, id in ipairs(siblings[entry.spellID] or {}) do if knownSpells[id] then return true end end
    return false
end

local CATALOG = {
    ["riposte"]={mode="reactive", reactive="riposte", duration=4},
    ["Ответный удар"]={mode="reactive", reactive="riposte", duration=4},
    ["surprise attack"]={mode="reactive", reactive="surprise", duration=4},
    ["Неожиданная атака"]={mode="reactive", reactive="surprise", duration=4},
    ["Внезапная атака"]={mode="reactive", reactive="surprise", duration=4},
    ["Внезапное нападение"]={mode="reactive", reactive="surprise", duration=4},
    ["ghostly strike"]={mode="auraCooldown", readyVisibility="hide"},
    ["Призрачный удар"]={mode="auraCooldown", readyVisibility="hide"},
    ["flourish"]={mode="auraCooldown", readyVisibility="hide"},
    ["blade flurry"]={mode="aura", inactiveVisibility="hide"},
    ["Шквал клинков"]={mode="aura", inactiveVisibility="hide"},
    ["adrenaline rush"]={mode="aura", inactiveVisibility="hide"},
    ["Выброс адреналина"]={mode="aura", inactiveVisibility="hide"},
    ["slice and dice"]={mode="aura", inactiveVisibility="hide"},
    ["Мясорубка"]={mode="aura", inactiveVisibility="hide"},
    ["envenom"]={mode="aura", inactiveVisibility="hide"},
    ["Отравление"]={mode="aura", inactiveVisibility="hide"},
    ["remorseless attacks"]={mode="aura", inactiveVisibility="hide"},
    ["Беспощадные атаки"]={mode="aura", inactiveVisibility="hide"},
    ["relentless strikes"]={mode="aura", inactiveVisibility="hide"},
    ["Неослабевающие удары"]={mode="aura", inactiveVisibility="hide"},
    ["taste for blood"]={mode="aura", inactiveVisibility="hide"},
    ["Вкус крови"]={mode="aura", inactiveVisibility="hide"},
}

local function catalogFor(id)
    local name = spellName(id)
    return CATALOG[name] or CATALOG[string.lower(name)]
end

local function entryDefaults(id, requestedMode)
    local cat = id > 0 and catalogFor(id)
    local mode = requestedMode or (cat and cat.mode) or "cooldown"
    if id < 0 then mode = "cooldown" end
    return {
        spellID=id, mode=mode, combined=false,
        readyVisibility=(cat and cat.readyVisibility) or "always",
        inactiveVisibility=(cat and cat.inactiveVisibility) or "show", duration=cat and cat.duration or nil,
        reactive=cat and cat.reactive or nil,
    }
end

-- Bar data -------------------------------------------------------------------

local function getBar(id)
    id = tonumber(id)
    if not profile or not id then return nil end
    for _, bar in ipairs(profile.bars) do if bar.id == id then return bar end end
end

local function barIndex(id)
    id = tonumber(id)
    for i, bar in ipairs(profile and profile.bars or {}) do if bar.id == id then return i end end
end

local function slotCount(bar)
    local n = 0
    for i, e in ipairs(bar.entries) do if i == 1 or not e.combined then n = n + 1 end end
    return n
end

local function normalizeCombined(bar)
    if bar.entries[1] then bar.entries[1].combined = false end
end

local function newBar(name)
    local id = profile.nextBarID
    profile.nextBarID = id + 1
    profile.bars[#profile.bars + 1] = {
        id=id, name=trim(name) ~= "" and trim(name) or ("Bar " .. id), rows=1, columns=4,
        size=36, spacing=4, growX="RIGHT", growY="DOWN", pos={"CENTER", 0, 0},
        anchor=nil, procCooldownMode="red", borderMode="eui", borderSource="MainBar",
        borderColor={r=0,g=0,b=0,a=1}, borderSize=1, procGlowEnabled=true,
        procGlowColor={r=1,g=0.82,b=0.1,a=1}, procGlowSize=8,
        fontFace="ellesmere", fontSize=14, fontOutline="OUTLINE", entries={},
    }
    changed()
    return id
end

-- Frames, movement and anchors -----------------------------------------------

local function frameCenter(frame)
    if not frame or not frame.GetCenter or not frame.GetEffectiveScale then return end
    local ok, x, y = pcall(frame.GetCenter, frame)
    if not ok or secret(x) or secret(y) or type(x) ~= "number" or type(y) ~= "number" then return end
    return x * frame:GetEffectiveScale() / UIParent:GetEffectiveScale(), y * frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

local function savePosition(bar)
    local row = rows[bar.id]
    local x, y = frameCenter(row)
    local px, py = frameCenter(UIParent)
    if x and px then bar.pos = {"CENTER", x - px, y - py} return true end
end

local function anchorFrame(bar, seen)
    local anchor = bar.anchor
    if type(anchor) ~= "table" then return nil end
    if type(anchor.barID) == "number" then
        local target = getBar(anchor.barID)
        seen = seen or {[bar.id]=true}
        local current = target
        while current and not seen[current.id] do
            seen[current.id] = true
            current = current.anchor and current.anchor.barID and getBar(current.anchor.barID) or nil
        end
        if current then return nil end
        return target and rows[target.id] or nil
    end
    local name = anchor.frame or anchor.name
    if type(name) ~= "string" or not name:match("^[%a_][%w_]*$") then return nil end
    local target = _G[name]
    if target and target.IsObjectType and target:IsObjectType("Frame") then return target end
end

local function applyPosition(bar)
    local row = rows[bar.id]
    if not row or row.dragging then return end
    if InCombatLockdown and InCombatLockdown() and row.positioned then return end
    local target = anchorFrame(bar)
    local pos, anchor = bar.pos or {"CENTER", 0, 0}, bar.anchor
    row:ClearAllPoints()
    local scale = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if target then
        row:SetPoint("CENTER", target, "CENTER", (anchor.x or 0) / scale, (anchor.y or 0) / scale)
    else
        row:SetPoint(pos[1] or "CENTER", UIParent, pos[1] or "CENTER", (pos[2] or 0) / scale, (pos[3] or 0) / scale)
    end
    row.positioned = true
    row.pendingAnchor = type(anchor) == "table" and target == nil or nil
end

local function movable() return (not db.settings.locked or editModeActive) and not (InCombatLockdown and InCombatLockdown()) end

local function updateInteraction(bar)
    local row = rows[bar.id]
    if not row then return end
    local canMove = movable()
    row:EnableMouse(canMove)
    row.bg:SetShown(canMove)
    row.label:SetShown(canMove)
    row.label:SetText("Forever CDM Advanced: " .. bar.name .. " (drag)")
end

local function euiBorder(bar)
    local eui = EllesmereUI
    local ns = eui and eui._ModuleNS and eui._ModuleNS["EllesmereUIActionBars"]
    local eab = ns and ns.EAB
    local euiProfile = eab and eab.db and eab.db.profile
    local settings = euiProfile and euiProfile.bars and euiProfile.bars[bar.borderSource]
    if not settings then return nil end
    local thickness, thicknessPx = settings.borderSize or 1
    if ns.ResolveBorderThickness then
        local ok, resolved, resolvedPx = pcall(ns.ResolveBorderThickness, settings)
        if ok then thickness, thicknessPx = resolved, resolvedPx end
    end
    thickness = tonumber(thickness) or 0
    local texture = type(settings.borderTexture) == "string" and settings.borderTexture or "solid"
    if thicknessPx and texture == "solid" then thickness = tonumber(thicknessPx) or thickness end
    local rawColor = type(settings.borderColor) == "table" and not secret(settings.borderColor)
        and not secretTable(settings.borderColor) and settings.borderColor or DEFAULT_BORDER_COLOR
    local color = {}
    for _, key in ipairs({"r", "g", "b", "a"}) do
        local component = rawColor[key]
        color[key] = not secret(component) and type(component) == "number" and component == component
            and component >= 0 and component <= 1 and component or DEFAULT_BORDER_COLOR[key]
    end
    if not secret(settings.borderClassColor) and settings.borderClassColor then
        local _, class = UnitClass("player")
        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if classColor then color.r, color.g, color.b = classColor.r, classColor.g, classColor.b end
    end
    local exactPx
    if eui.BorderPx then
        local ok, value = pcall(eui.BorderPx, settings.borderThicknessPx, thickness, texture)
        if ok then exactPx = value end
    end
    local signature = table.concat({
        "eui", bar.borderSource, texture, tostring(thickness), tostring(thicknessPx),
        tostring(color.r), tostring(color.g), tostring(color.b), tostring(color.a),
        tostring(settings.borderTextureOffset), tostring(settings.borderTextureOffsetY),
        tostring(settings.borderTextureShiftX), tostring(settings.borderTextureShiftY),
        tostring(settings.borderThickness), tostring(settings.borderThicknessPx),
        tostring(settings.borderBehind), tostring(settings.borderAboveEffects), tostring(exactPx),
        tostring(eui.ApplyBorderStyle),
    }, ":")
    return {eui=eui, settings=settings, texture=texture, thickness=math.max(0, thickness),
        color=color, exactPx=exactPx, signature=signature}
end

local function hideBorderVisuals(f)
    for _, line in ipairs(f.borderLines) do line:Hide() end
    if f.ppBorder and EllesmereUI and EllesmereUI.PP then pcall(EllesmereUI.PP.HideBorder, f) end
    if EllesmereUI and EllesmereUI.ApplyBorderStyle then
        pcall(EllesmereUI.ApplyBorderStyle, f.borderHost, 0, 0, 0, 0, 0, "solid")
    end
    f.borderHost:Hide()
end

local function showLineBorder(f, size, color)
    if size <= 0 then return end
    local top, bottom, left, right = unpack(f.borderLines)
    for _, line in ipairs(f.borderLines) do line:SetColorTexture(color.r, color.g, color.b, color.a) line:Show() end
    top:ClearAllPoints(); top:SetPoint("TOPLEFT", f, "TOPLEFT"); top:SetPoint("TOPRIGHT", f, "TOPRIGHT"); top:SetHeight(size)
    bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT"); bottom:SetHeight(size)
    left:ClearAllPoints(); left:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT"); left:SetWidth(size)
    right:ClearAllPoints(); right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT"); right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT"); right:SetWidth(size)
end

local FONT_PATHS = {friz=[[Fonts\FRIZQT__.TTF]], arial=[[Fonts\ARIALN.TTF]],
    skurri=[[Fonts\skurri.ttf]], morpheus=[[Fonts\MORPHEUS.ttf]]}
local iconSerial = 0

local function fontPath(face)
    if face == "ellesmere" then
        if EllesmereUI and EllesmereUI.GetFontPath then
            local ok, path = pcall(EllesmereUI.GetFontPath, "actionBars")
            if ok and type(path) == "string" and not secret(path) and path ~= "" then return path end
        end
        return [[Fonts\FRIZQT__.TTF]]
    end
    return FONT_PATHS[face] or [[Fonts\FRIZQT__.TTF]]
end

local function applyFont(f, path, size, outline)
    local flags = outline == "NONE" and "" or outline
    local fallback = [[Fonts\FRIZQT__.TTF]]
    local countdown
    if f.cd.GetCountdownFontString then
        local ok, value = pcall(f.cd.GetCountdownFontString, f.cd)
        if ok then countdown = value end
    end
    if countdown and countdown.SetFont then
        local ok, applied = pcall(countdown.SetFont, countdown, path, size, flags)
        if not ok or applied == false then pcall(countdown.SetFont, countdown, fallback, size, flags) end
    elseif f.cd.SetCountdownFont then
        if not f.countdownFont then
            f.countdownFontName = "ForeverCDMAdvancedCountdownFont" .. f.serial
            f.countdownFont = CreateFont(f.countdownFontName)
        end
        local ok, applied = pcall(f.countdownFont.SetFont, f.countdownFont, path, size, flags)
        if not ok or applied == false then pcall(f.countdownFont.SetFont, f.countdownFont, fallback, size, flags) end
        if f.countdownFont then
            pcall(f.cd.SetCountdownFont, f.cd, f.countdownFontName)
        end
    end
    local ok, applied = pcall(f.count.SetFont, f.count, path, size, flags)
    if not ok or applied == false then pcall(f.count.SetFont, f.count, fallback, size, flags) end
end

local function applyAppearance(f, bar)
    local eui = bar.borderMode == "eui" and euiBorder(bar) or nil
    local path = fontPath(bar.fontFace)
    local borderSignature
    if bar.borderMode == "eui" then
        borderSignature = eui and eui.signature or table.concat({"fallback", bar.borderColor.r, bar.borderColor.g,
            bar.borderColor.b, bar.borderColor.a, bar.borderSize}, ":")
    else
        borderSignature = table.concat({bar.borderMode, bar.borderColor.r, bar.borderColor.g,
            bar.borderColor.b, bar.borderColor.a, bar.borderSize}, ":")
    end
    local signature = table.concat({borderSignature, path, bar.fontSize, bar.fontOutline}, "|")
    if f.appearanceSignature == signature then return end
    f.appearanceSignature = signature
    hideBorderVisuals(f)
    if bar.borderMode == "solid" then
        showLineBorder(f, bar.borderSize, bar.borderColor)
    elseif bar.borderMode == "eui" and eui then
        local settings = eui.settings
        if eui.texture ~= "" and eui.texture ~= "solid" and eui.eui.ApplyBorderStyle and eui.thickness > 0 then
            f.borderHost:ClearAllPoints()
            f.borderHost:SetAllPoints(f)
            local baseLevel = f:GetFrameLevel() or 1
            if settings.borderBehind then f.borderHost:SetFrameLevel(math.max(0, baseLevel - 1))
            elseif settings.borderAboveEffects then f.borderHost:SetFrameLevel(baseLevel + 8)
            else f.borderHost:SetFrameLevel(baseLevel + 2) end
            local ok = pcall(eui.eui.ApplyBorderStyle, f.borderHost, eui.thickness,
                eui.color.r, eui.color.g, eui.color.b, eui.color.a, eui.texture,
                settings.borderTextureOffset, settings.borderTextureOffsetY,
                settings.borderTextureShiftX, settings.borderTextureShiftY,
                "actionbars", settings.borderThickness or "thin", nil, eui.exactPx)
            if ok then f.borderHost:Show() else showLineBorder(f, eui.thickness, eui.color) end
        elseif eui.texture == "solid" and eui.thickness > 0 and eui.eui.PP then
            local pp = eui.eui.PP
            if not f.ppBorder then
                local ok = pcall(pp.CreateBorder, f, 0, 0, 0, 1, 1, "OVERLAY", -1)
                f.ppBorder = ok and true or nil
            end
            if f.ppBorder then
                pcall(pp.UpdateBorder, f, eui.thickness, eui.color.r, eui.color.g, eui.color.b, eui.color.a)
                pcall(pp.ShowBorder, f)
            else
                showLineBorder(f, eui.thickness, eui.color)
            end
        else
            showLineBorder(f, eui.thickness, eui.color)
        end
    elseif bar.borderMode == "eui" then
        showLineBorder(f, bar.borderSize, bar.borderColor)
    end
    applyFont(f, path, bar.fontSize, bar.fontOutline)
end

local function newIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    iconSerial = iconSerial + 1
    f.serial = iconSerial
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetDrawEdge(true)
    f.cd:SetHideCountdownNumbers(false)
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetPoint("TOP", f, "BOTTOM", 0, -1)
    f.proc = f:CreateTexture(nil, "OVERLAY", nil, 5)
    f.proc:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.proc:SetBlendMode("ADD")
    f.proc:Hide()
    f.borderLines = {}
    for i = 1, 4 do f.borderLines[i] = f:CreateTexture(nil, "OVERLAY", nil, 7) end
    f.borderHost = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.borderHost:SetAllPoints(f)
    f.borderHost:EnableMouse(false)
    f.borderHost:Hide()
    if not cooldownDriver then
        cooldownDriver = CreateFrame("Frame", nil, UIParent)
        cooldownDriver:SetSize(1, 1)
        cooldownDriver:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT")
        cooldownDriver:EnableMouse(false)
        cooldownDriver:SetAlpha(0)
        cooldownDriver:Show()
    end
    f.cdTracker = CreateFrame("Cooldown", nil, cooldownDriver, "CooldownFrameTemplate")
    f.cdTracker:SetSize(1, 1)
    f.cdTracker:SetPoint("BOTTOMLEFT", cooldownDriver, "BOTTOMLEFT")
    f.cdTracker:SetAlpha(0)
    f.cdTracker:SetHideCountdownNumbers(true)
    if f.cdTracker.SetDrawSwipe then f.cdTracker:SetDrawSwipe(false) end
    if f.cdTracker.SetDrawEdge then f.cdTracker:SetDrawEdge(false) end
    f.trackerProxy = {cd=f.cdTracker, count={SetText=function() end}}
    f:EnableMouse(false)
    f.cd:SetScript("OnCooldownDone", function()
        if f.callbackGeneration ~= runtimeGeneration then return end
        local uid = f.cooldownUID
        local auraUID = f.auraUID
        if uid == f.uid then
            local runtime = uid and entryRuntime[uid]
            if runtime and runtime.latched then
                runtime.latched, runtime.latchedAt = nil, nil
                f.cooldownUID = nil
                refreshAll()
            end
        elseif auraUID == f.uid then
            local runtime = entryRuntime[auraUID]
            if runtime then
                runtime.knownActive, runtime.auraInstanceID, runtime.knownExpires = nil, nil, nil
                runtime.knownTargetGUID = nil
            end
            f.auraUID = nil
            refreshAll()
        end
    end)
    f.cdTracker:SetScript("OnCooldownDone", function()
        if f.trackerGeneration ~= runtimeGeneration or f.trackerUID ~= f.uid then return end
        local uid = f.trackerUID
        f.trackerUID = nil
        local runtime = uid and entryRuntime[uid]
        if runtime then runtime.latched, runtime.latchedAt = nil, nil end
        refreshAll()
    end)
    return f
end

local function stopDrag(bar)
    local row = rows[bar.id]
    if not row or not row.dragging then return end
    row:StopMovingOrSizing()
    row.dragging = nil
    savePosition(bar)
    if type(bar.anchor) == "table" then
        local target = anchorFrame(bar)
        local x, y = frameCenter(row)
        local tx, ty = frameCenter(target)
        if x and tx then bar.anchor.x, bar.anchor.y = x - tx, y - ty end
    end
    applyPosition(bar)
    configChanged()
end

local function showAnchorMenu(bar)
    if not editModeActive or not movable() then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        say("use /fcdma anchor %d <barID|FrameName|none>", bar.id)
        return
    end
    MenuUtil.CreateContextMenu(rows[bar.id], function(_, root)
        root:CreateTitle("Forever CDM Advanced: " .. bar.name)
        root:CreateRadio("Screen (detach)", function() return bar.anchor == nil end, function()
            ForeverCDMAdvanced.SetBarOption(bar.id, "anchor", nil)
        end)
        for _, other in ipairs(profile.bars) do
            if other.id ~= bar.id then
                local target = other
                root:CreateRadio("Forever CDM Advanced: " .. target.name,
                    function() return bar.anchor and bar.anchor.barID == target.id end,
                    function() ForeverCDMAdvanced.SetBarOption(bar.id, "anchor", target.id) end)
            end
        end
        local manager = EditModeManagerFrame
        for _, frame in ipairs(manager and manager.registeredSystemFrames or {}) do
            local name = frame and frame.GetName and frame:GetName()
            if name and frame ~= UIParent and frame ~= rows[bar.id] then
                local label = frame.GetSystemName and frame:GetSystemName() or name
                root:CreateRadio(label,
                    function() return bar.anchor and bar.anchor.frame == name end,
                    function() ForeverCDMAdvanced.SetBarOption(bar.id, "anchor", name) end)
            end
        end
    end)
end

local function createRow(bar)
    local row = CreateFrame("Frame", "ForeverCDMAdvancedBar" .. bar.id, UIParent)
    row:SetMovable(true)
    row:SetClampedToScreen(true)
    row:RegisterForDrag("LeftButton")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.82, 0.38, 0.12, 0.25)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("BOTTOM", row, "TOP", 0, 2)
    row:SetScript("OnDragStart", function(self)
        if movable() then self.dragging = true self:StartMoving() end
    end)
    row:SetScript("OnDragStop", function(self) stopDrag(self.bar) end)
    row:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then showAnchorMenu(self.bar) end end)
    row.bar = bar
    row.positioned = false
    rows[bar.id], icons[bar.id] = row, icons[bar.id] or {}
    return row
end

local function reconcileRows()
    local wanted = {}
    for _, bar in ipairs(profile.bars) do
        wanted[bar.id] = true
        if not rows[bar.id] then createRow(bar) end
        if rows[bar.id].bar ~= bar then rows[bar.id].positioned = false end
        rows[bar.id].bar = bar
    end
    for id, row in pairs(rows) do
        if not wanted[id] then row:Hide() end
    end
end

-- Cooldowns and auras ---------------------------------------------------------

local function clearCooldown(f)
    if f.cd.Clear then f.cd:Clear() else f.cd:SetCooldown(0, 0) end
end

local function resetTracker(f)
    f.trackerUID, f.trackerGeneration = nil, nil
    if f.cdTracker.Clear then f.cdTracker:Clear() else f.cdTracker:SetCooldown(0, 0) end
end

local function resetIconTransient(f)
    f.proc:Hide()
end

-- Returns true/false when readable and nil when the client only exposes a duration object.
local function drawSpellCooldown(f, id)
    local c = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
    if secret(c) or secretTable(c) then
        local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id)
        if duration and f.cd.SetCooldownFromDurationObject then f.cd:SetCooldownFromDurationObject(duration) else clearCooldown(f) end
        return nil
    end
    if type(c) ~= "table" then clearCooldown(f) return false end
    if secret(c.startTime) or secret(c.duration) or secret(c.isEnabled) then
        local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id)
        if duration and f.cd.SetCooldownFromDurationObject then f.cd:SetCooldownFromDurationObject(duration) else clearCooldown(f) end
        return nil
    end
    local rate = not secret(c.modRate) and (c.modRate or 1) or 1
    f.cd:SetCooldown(c.startTime or 0, c.duration or 0, rate)
    return (c.duration or 0) > 1.5 and c.isEnabled ~= false
end

local function drawItemCooldown(f, id)
    local start, duration, enabled
    if C_Container and C_Container.GetItemCooldown then start, duration, enabled = C_Container.GetItemCooldown(-id) end
    if secret(start) or secret(duration) or secret(enabled) then clearCooldown(f) return nil end
    f.cd:SetCooldown(start or 0, duration or 0)
    return (duration or 0) > 1.5 and enabled ~= 0 and enabled ~= false
end

local function drawCooldown(f, id)
    f.itemMissing = nil
    local onCD = id < 0 and drawItemCooldown(f, id) or drawSpellCooldown(f, id)
    local count
    if id < 0 then
        count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(-id, false, true)
        if not secret(count) and type(count) == "number" and count <= 0 then f.itemMissing = true end
    else
        local ch = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(id)
        if secret(ch) or secretTable(ch) then
            local duration = C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(id)
            if duration and f.cd.SetCooldownFromDurationObject then f.cd:SetCooldownFromDurationObject(duration) onCD = nil end
        elseif type(ch) == "table" and not secret(ch.maxCharges) and not secret(ch.currentCharges) then
            local maximum, current = ch.maxCharges or 0, ch.currentCharges or 0
            if maximum > 1 then
                count = current
                if current < maximum then
                    local duration = C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(id)
                    if duration and f.cd.SetCooldownFromDurationObject then
                        f.cd:SetCooldownFromDurationObject(duration)
                    elseif not secret(ch.cooldownStartTime) and not secret(ch.cooldownDuration) then
                        f.cd:SetCooldown(ch.cooldownStartTime or 0, ch.cooldownDuration or 0)
                    end
                    onCD = true
                end
            end
        end
    end
    f.count:SetText(not secret(count) and count ~= nil and tostring(count) or "")
    return onCD
end

local function trackCooldown(f, entry)
    if f.trackerUID == entry.uid and f.trackerGeneration == runtimeGeneration then return end
    resetTracker(f)
    local onCD = drawCooldown(f.trackerProxy, entry.spellID)
    if onCD ~= false then f.trackerUID, f.trackerGeneration = entry.uid, runtimeGeneration end
end

local function spellAuraRestricted(id)
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return false end
    local okGlobal, global = pcall(C_Secrets.ShouldAurasBeSecret)
    if not okGlobal or secret(global) or global ~= true then return false end
    if C_Secrets.ShouldSpellAuraBeSecret then
        local okSpell, restricted = pcall(C_Secrets.ShouldSpellAuraBeSecret, id)
        if okSpell and not secret(restricted) and restricted == false then return false end
    end
    return true
end

local function auraForPlayer(id)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil, true end
    local restricted = spellAuraRestricted(id)
    local ids = siblings[id] or {id}
    for _, sid in ipairs(ids) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if not ok then return nil, false end
        if secret(aura) or secretTable(aura) then return nil, false end
        if aura ~= nil then return aura, true end
    end
    return nil, not restricted
end

local function auraForTarget(id)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil, false end
    local restricted = spellAuraRestricted(id)
    local name = spellName(id)
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL|PLAYER")
        if not ok then return nil, false end
        if secret(aura) or secretTable(aura) then return nil, false end
        if aura == nil then return nil, not restricted end
        if secret(aura.spellId) then return nil, false end
        if aura.spellId == id or (not secret(aura.name) and aura.name == name) then return aura, true end
    end
    return nil, not restricted
end

local function currentTargetGUID()
    if not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, "target")
    if not ok or secret(guid) then return nil end
    return guid
end

local function catalogDuration(entry)
    local cat = catalogFor(entry.spellID)
    return entry.duration or entry.learnedDuration or (cat and cat.duration)
end

local function drawAura(f, unit, aura, entry)
    local duration, expires = aura.duration, aura.expirationTime
    if secret(duration) or secret(expires) then
        local object
        if C_UnitAuras.GetAuraDuration and not secret(aura.auraInstanceID) and aura.auraInstanceID ~= nil then
            local ok, value = pcall(C_UnitAuras.GetAuraDuration, unit, aura.auraInstanceID)
            if ok then object = value end
        end
        if object and f.cd.SetCooldownFromDurationObject then f.cd:SetCooldownFromDurationObject(object) else clearCooldown(f) end
    elseif type(duration) == "number" and duration > 0 and type(expires) == "number" then
        f.cd:SetCooldown(expires - duration, duration)
        if entry.duration == nil and entry.learnedDuration ~= duration then
            entry.learnedDuration = duration
            configChanged()
        end
    else clearCooldown(f) end
    if not secret(aura.applications) and (aura.applications or 0) > 1 then f.count:SetText(aura.applications) else f.count:SetText("") end
end

local function readyVisible(entry)
    return entry.readyVisibility == "always" or (entry.readyVisibility == "combat" and inCombat)
end

local function stateForEntry(f, entry, bar, final)
    f.cooldownUID, f.auraUID = nil, nil
    local state = {entry=entry, visible=true, alpha=1, active=false, desaturated=false}
    local runtime = entryRuntime[entry.uid]
    if not entryAvailable(entry) then
        if final then resetTracker(f) end
        clearCooldown(f)
        f.count:SetText("")
        state.visible = not db.settings.locked or editModeActive
        state.alpha, state.desaturated, state.unavailable = 0.2, true, true
        return state
    end
    if entry.mode == "reactive" then
        runtime = runtime or {}
        entryRuntime[entry.uid] = runtime
        local now = GetTime()
        local proc = runtime.procUntil and now < runtime.procUntil
        if proc and entry.reactive == "surprise" and runtime.targetGUID then
            local current = currentTargetGUID()
            if current and current ~= runtime.targetGUID then proc = false end
        end
        local latched = runtime.latched
        if proc then
            local onCD = drawCooldown(f, entry.spellID)
            local waiting = latched and onCD == false and runtime.latchedAt and now - runtime.latchedAt < 0.75
            if latched and onCD == false and not waiting then
                runtime.latched, runtime.latchedAt = nil, nil
                latched = nil
            end
            local blocked = onCD == true or (latched and (onCD == nil or waiting))
            if final then
                if blocked then trackCooldown(f, entry) else resetTracker(f) end
            end
            state.active = true
            state.proc = true
            state.red = blocked and bar.procCooldownMode == "red"
            state.visible = not (blocked and bar.procCooldownMode == "hide")
            f.cooldownUID = nil
            f.cd:SetCooldown(runtime.procAt or now, math.max(0.1, (runtime.procUntil or now) - (runtime.procAt or now)))
        elseif latched then
            if final then resetTracker(f) end
            local onCD = drawCooldown(f, entry.spellID)
            local waiting = onCD == false and runtime.latchedAt and now - runtime.latchedAt < 0.75
            state.active, state.desaturated = onCD ~= false or waiting, onCD ~= false
            state.visible = onCD ~= false or waiting
            if onCD == false and not waiting then runtime.latched, runtime.latchedAt = nil, nil
            elseif onCD ~= false then f.cooldownUID = entry.uid end
        else
            if final then resetTracker(f) end
            f.cooldownUID = nil
            clearCooldown(f)
            state.visible = not db.settings.locked or editModeActive
            state.alpha, state.desaturated = 0.25, true
        end
        return state
    end

    if entry.mode == "cooldown" then
        if final then resetTracker(f) end
        local onCD = drawCooldown(f, entry.spellID)
        state.active, state.desaturated = onCD ~= false, onCD == true
        state.visible = onCD ~= false or readyVisible(entry) or not db.settings.locked or editModeActive
        if f.itemMissing then state.active, state.alpha, state.desaturated = false, 0.25, true end
        return state
    end

    local aura, readable
    if final then resetTracker(f) end
    if entry.mode == "debuff" then aura, readable = auraForTarget(entry.auraID or entry.spellID)
    else aura, readable = auraForPlayer(entry.auraID or entry.spellID) end
    local runtimeState = entryRuntime[entry.uid]
    if aura then
        runtimeState = runtimeState or {}
        entryRuntime[entry.uid] = runtimeState
        runtimeState.castAt = nil
        runtimeState.knownActive = true
        if not secret(aura.auraInstanceID) then runtimeState.auraInstanceID = aura.auraInstanceID end
        if not secret(aura.expirationTime) and type(aura.expirationTime) == "number" then runtimeState.knownExpires = aura.expirationTime end
        if entry.mode == "debuff" then runtimeState.knownTargetGUID = currentTargetGUID() end
        state.active = true
        drawAura(f, entry.mode == "debuff" and "target" or "player", aura, entry)
        if secret(aura.duration) or secret(aura.expirationTime) then f.auraUID = entry.uid end
        return state
    end

    local estimate = runtimeState and runtimeState.castAt
    if entry.mode == "debuff" and runtimeState then
        local current = currentTargetGUID()
        local cast = current and runtimeState.casts and runtimeState.casts[current]
        estimate = cast and cast.at or nil
    end
    local duration = catalogDuration(entry)
    if readable and estimate and GetTime() - estimate <= 1 then
        state.active, state.alpha = true, 0.85
        if duration then f.cd:SetCooldown(estimate, duration) else clearCooldown(f) end
        return state
    end
    if not readable and estimate and duration and GetTime() < estimate + duration then
        state.active, state.alpha = true, 0.85
        f.cd:SetCooldown(estimate, duration)
        return state
    end
    local knownHere = runtimeState and runtimeState.knownActive
    if knownHere and runtimeState.knownExpires and GetTime() >= runtimeState.knownExpires then knownHere = false end
    if knownHere and entry.mode == "debuff" then
        local current = currentTargetGUID()
        knownHere = current ~= nil and current == runtimeState.knownTargetGUID
    end
    if not readable and knownHere then
        local object
        if runtimeState.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration then
            local unit = entry.mode == "debuff" and "target" or "player"
            local ok, value = pcall(C_UnitAuras.GetAuraDuration, unit, runtimeState.auraInstanceID)
            if ok then object = value end
        end
        if object and f.cd.SetCooldownFromDurationObject then f.cd:SetCooldownFromDurationObject(object) end
        if object then f.auraUID = entry.uid end
        state.active, state.alpha, state.visible = true, 0.85, true
        return state
    end
    if readable and runtimeState then
        runtimeState.knownActive, runtimeState.auraInstanceID, runtimeState.knownExpires = nil, nil, nil
        runtimeState.knownTargetGUID = nil
        if entry.mode == "debuff" then
            local current = currentTargetGUID()
            if current and runtimeState.casts then runtimeState.casts[current] = nil end
        else
            runtimeState.castAt = nil
        end
    end
    if entry.mode == "auraCooldown" then
        local onCD = drawCooldown(f, entry.spellID)
        state.active, state.desaturated = onCD ~= false, onCD == true
        state.visible = onCD ~= false or readyVisible(entry) or not db.settings.locked or editModeActive
        return state
    end
    clearCooldown(f)
    state.alpha, state.desaturated = 0.25, true
    state.visible = entry.inactiveVisibility ~= "hide" or not db.settings.locked or editModeActive
    return state
end

local function groupsFor(bar)
    local groups = {}
    for i, entry in ipairs(bar.entries) do
        if i > 1 and entry.combined then groups[#groups][#groups[#groups] + 1] = entry
        else groups[#groups + 1] = {entry} end
    end
    return groups
end

local function layoutBar(bar)
    local row, list = rows[bar.id], icons[bar.id]
    local groups, visible = groupsFor(bar), {}
    local entryFrame = {}
    for slot, members in ipairs(groups) do
        local f = list[slot]
        if not f then f = newIcon(row) list[slot] = f end
        f:SetSize(bar.size, bar.size)
        applyAppearance(f, bar)
        resetIconTransient(f)
        f.cooldownUID, f.auraUID = nil, nil
        local chosen, chosenState
        for _, entry in ipairs(members) do
            f.cooldownUID, f.auraUID = nil, nil
            clearCooldown(f)
            f.count:SetText("")
            local state = stateForEntry(f, entry, bar, false)
            entryFrame[entry.uid] = f
            if not chosenState or (state.active and not chosenState.active) or (state.visible and not chosenState.visible) then
                chosen, chosenState = entry, state
            end
        end
        chosen, chosenState = chosen or members[1], chosenState or {visible=false}
        -- Redraw the selected member because probing later combined members reuses this widget.
        f.cooldownUID, f.auraUID = nil, nil
        clearCooldown(f)
        f.count:SetText("")
        f.uid = chosen.uid
        f.callbackGeneration = runtimeGeneration
        if f.trackerUID and (f.trackerUID ~= chosen.uid or f.trackerGeneration ~= runtimeGeneration) then resetTracker(f) end
        chosenState = stateForEntry(f, chosen, bar, true)
        f.entryIndex = nil
        f.icon:SetTexture(spellIcon(chosen.spellID))
        f.name:SetText(spellName(chosen.spellID))
        f.name:SetShown(db.settings.showNames)
        f:SetAlpha(chosenState.alpha or 1)
        f.icon:SetDesaturated(chosenState.desaturated or false)
        local showProc = chosenState.proc and bar.procGlowEnabled
        if showProc then
            local glowSize, color = bar.procGlowSize, bar.procGlowColor
            f.proc:ClearAllPoints()
            f.proc:SetPoint("TOPLEFT", f, "TOPLEFT", -glowSize, glowSize)
            f.proc:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", glowSize, -glowSize)
            if chosenState.red then f.proc:SetVertexColor(1, 0, 0, color.a)
            else f.proc:SetVertexColor(color.r, color.g, color.b, color.a) end
        end
        f.proc:SetShown(showProc or false)
        if chosenState.visible then visible[#visible + 1] = f f:Show() else f:Hide() end
    end
    for i = #groups + 1, #list do
        local f = list[i]
        f.cooldownUID, f.auraUID, f.uid, f.callbackGeneration = nil, nil, nil, nil
        clearCooldown(f)
        resetIconTransient(f)
        resetTracker(f)
        f:Hide()
    end
    for index, entry in ipairs(bar.entries) do
        local f = entryFrame[entry.uid]
        if f and not f.entryIndex then f.entryIndex = index end
    end
    for index, f in ipairs(visible) do
        local zero = index - 1
        local gridRow, col = math.floor(zero / bar.columns), zero % bar.columns
        local x = col * (bar.size + bar.spacing) * (bar.growX == "LEFT" and -1 or 1)
        local y = gridRow * (bar.size + bar.spacing) * (bar.growY == "UP" and 1 or -1)
        local point = (bar.growY == "UP" and "BOTTOM" or "TOP") .. (bar.growX == "LEFT" and "RIGHT" or "LEFT")
        f:ClearAllPoints()
        f:SetPoint(point, row, point, x, y)
    end
    local width = bar.columns * bar.size + math.max(0, bar.columns - 1) * bar.spacing
    local height = bar.rows * bar.size + math.max(0, bar.rows - 1) * bar.spacing
    row:SetSize(math.max(40, width), math.max(20, height))
    updateInteraction(bar)
    row:SetShown(#visible > 0 or not db.settings.locked or editModeActive)
end

local function targetEnemy()
    if not (UnitExists and UnitCanAttack) then return false end
    local okExists, exists = pcall(UnitExists, "target")
    if not okExists or secret(exists) then return true end
    if exists ~= true then return false end
    local okAttack, attack = pcall(UnitCanAttack, "player", "target")
    if not okAttack or secret(attack) then return true end
    return attack == true
end

local function applyFade()
    local alpha = 1
    local settings = db.settings
    if settings.fade and settings.locked and not editModeActive and not inCombat and not targetEnemy() then alpha = settings.fade == "hide" and 0 or 0.3 end
    for _, bar in ipairs(profile.bars) do if rows[bar.id] then rows[bar.id]:SetAlpha(alpha) end end
end

refreshAll = function()
    if not db or not profile then return end
    reconcileRows()
    for _, bar in ipairs(profile.bars) do
        layoutBar(bar)
        local row = rows[bar.id]
        if row and (not row.positioned or row.pendingAnchor) then applyPosition(bar) end
    end
    applyFade()
end

local function updateInteractions(stop)
    for _, bar in ipairs(profile.bars) do if stop then stopDrag(bar) end updateInteraction(bar) end
    refreshAll()
end

local function initEditMode()
    if not (EventRegistry and EventRegistry.RegisterCallback) then return end
    EventRegistry:RegisterCallback("EditMode.Enter", function() editModeActive = true updateInteractions(true) end, rows)
    EventRegistry:RegisterCallback("EditMode.Exit", function() editModeActive = false updateInteractions(true) end, rows)
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive then
        local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
        editModeActive = ok and not secret(active) and active == true
    end
end

-- Public API -----------------------------------------------------------------

ForeverCDMAdvanced = ForeverCDMAdvanced or {}
local API = ForeverCDMAdvanced

function API.GetDB() return db end
function API.GetActiveProfile() return profile end
function API.GetBars() return profile and profile.bars or {} end
function API.GetBar(id) return getBar(id) end
function API.GetBarFrame(id) return getBar(id) and rows[tonumber(id)] or nil end
function API.GetEntryFrame(barID, index)
    local bar, wanted = getBar(barID), tonumber(index)
    if not bar or not bar.entries[wanted] then return nil end
    local uid, groups = bar.entries[wanted].uid, groupsFor(bar)
    for slot, f in ipairs(icons[bar.id] or {}) do
        for _, member in ipairs(groups[slot] or {}) do if member.uid == uid then return f end end
    end
end
function API.CreateBar(name)
    if InCombatLockdown and InCombatLockdown() then return nil, "bars cannot be created in combat" end
    return newBar(name)
end

function API.DeleteBar(id)
    local index, bar = barIndex(id), getBar(id)
    if not index then return false, "bar not found" end
    stopDrag(bar)
    savePosition(bar)
    for _, entry in ipairs(bar.entries) do entryRuntime[entry.uid] = nil end
    for _, icon in ipairs(icons[bar.id] or {}) do
        icon.cooldownUID, icon.auraUID, icon.uid, icon.callbackGeneration = nil, nil, nil, nil
        clearCooldown(icon)
        resetIconTransient(icon)
        resetTracker(icon)
        icon:Hide()
    end
    for _, dependent in ipairs(profile.bars) do
        if dependent.anchor and dependent.anchor.barID == bar.id then
            savePosition(dependent)
            dependent.anchor = nil
            if rows[dependent.id] then rows[dependent.id].positioned = false end
        end
    end
    table.remove(profile.bars, index)
    if rows[bar.id] then rows[bar.id]:Hide() end
    changed()
    return true
end

function API.RenameBar(id, name)
    local bar = getBar(id)
    name = trim(name)
    if not bar then return false, "bar not found" end
    if name == "" then return false, "name is empty" end
    bar.name = name
    changed()
    return true
end

function API.SetBarOption(id, key, value)
    local bar = getBar(id)
    if not bar then return false, "bar not found" end
    if key == "rows" or key == "columns" then
        value = tonumber(value)
        if not value or value < 1 or value > 20 or value ~= math.floor(value) then return false, "grid value must be an integer from 1 to 20" end
        local rowsN, colsN = key == "rows" and value or bar.rows, key == "columns" and value or bar.columns
        if rowsN * colsN < slotCount(bar) then return false, "grid is smaller than the used visual slots" end
    elseif key == "size" then
        value = tonumber(value)
        if not value or value < 12 or value > 96 then return false, "size must be 12-96" end
    elseif key == "spacing" then
        value = tonumber(value)
        if not value or value < 0 or value > 30 then return false, "spacing must be 0-30" end
    elseif key == "growX" then
        value = type(value) == "string" and string.upper(value)
        if not GROW_X[value] then return false, "growX must be RIGHT or LEFT" end
    elseif key == "growY" then
        value = type(value) == "string" and string.upper(value)
        if not GROW_Y[value] then return false, "growY must be DOWN or UP" end
    elseif key == "procCooldownMode" then
        if not PROC_CD[value] then return false, "procCooldownMode must be red or hide" end
    elseif key == "borderMode" then
        if secret(value) or not BORDER_MODES[value] then return false, "borderMode must be eui, solid, or none" end
    elseif key == "borderSource" then
        if secret(value) or not BORDER_SOURCES[value] then return false, "borderSource must be MainBar or Bar2-Bar10" end
    elseif key == "borderColor" or key == "procGlowColor" then
        value = validColor(value)
        if not value then return false, key .. " must contain numeric r, g, b, a values from 0 to 1" end
    elseif key == "borderSize" then
        if secret(value) then return false, "borderSize must be 0-8" end
        value = tonumber(value)
        if not value or value ~= value or value < 0 or value > 8 then return false, "borderSize must be 0-8" end
    elseif key == "procGlowEnabled" then
        if secret(value) or type(value) ~= "boolean" then return false, "procGlowEnabled must be a boolean" end
    elseif key == "procGlowSize" then
        if secret(value) then return false, "procGlowSize must be 0-20" end
        value = tonumber(value)
        if not value or value ~= value or value < 0 or value > 20 then return false, "procGlowSize must be 0-20" end
    elseif key == "fontFace" then
        if secret(value) or not FONT_FACES[value] then return false, "fontFace must be ellesmere, friz, arial, skurri, or morpheus" end
    elseif key == "fontSize" then
        if secret(value) then return false, "fontSize must be 6-64" end
        value = tonumber(value)
        if not value or value ~= value or value < 6 or value > 64 then return false, "fontSize must be 6-64" end
    elseif key == "fontOutline" then
        if secret(value) or not FONT_OUTLINES[value] then return false, "fontOutline must be NONE, OUTLINE, or THICKOUTLINE" end
    elseif key == "pos" then
        local valid = {CENTER=true, TOP=true, BOTTOM=true, LEFT=true, RIGHT=true,
            TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true}
        if type(value) ~= "table" or not valid[value[1]] or type(value[2]) ~= "number" or type(value[3]) ~= "number" then return false, "invalid position" end
        value = {value[1], value[2], value[3]}
    elseif key == "anchor" then
        if value == nil and bar.anchor then savePosition(bar) end
        if type(value) == "number" then value = {barID=value}
        elseif type(value) == "string" then value = {frame=value}
        elseif value ~= nil and type(value) ~= "table" then return false, "invalid anchor" end
        if value and value.target and not value.barID and not value.frame then
            if type(value.target) == "number" then value.barID = value.target else value.frame = value.target end
        end
        if value and value.frame and _G[value.frame] then
            for otherID, row in pairs(rows) do
                if _G[value.frame] == row then value = {barID=otherID} break end
            end
        end
        if value and value.barID then
            value.barID = tonumber(value.barID)
            if value.barID == bar.id or not getBar(value.barID) then return false, "invalid anchor bar" end
            local current, seen = getBar(value.barID), {}
            while current and not seen[current.id] do
                if current.id == bar.id then return false, "anchor would create a cycle" end
                seen[current.id] = true
                current = current.anchor and current.anchor.barID and getBar(current.anchor.barID) or nil
            end
        end
        if value and value.frame and (type(value.frame) ~= "string" or not value.frame:match("^[%a_][%w_]*$")) then return false, "invalid anchor frame" end
        if value and value.frame and rows[bar.id] and value.frame == rows[bar.id]:GetName() then return false, "bar cannot anchor to itself" end
        if value and value.x == nil then
            local target = value.barID and rows[value.barID] or value.frame and _G[value.frame]
            local x, y = frameCenter(rows[bar.id])
            local tx, ty = frameCenter(target)
            value.x, value.y = x and tx and x - tx or 0, y and ty and y - ty or 0
        end
    else return false, "unknown bar option" end
    bar[key] = value
    if (key == "pos" or key == "anchor") and rows[bar.id] then rows[bar.id].positioned = false end
    changed()
    return true
end

function API.AddEntry(barID, spellOrID, requestedMode)
    local bar, id = getBar(barID), resolveSpell(spellOrID)
    if not bar then return false, "bar not found" end
    if not id then return false, "spell or item not found" end
    if requestedMode and not MODES[requestedMode] then return false, "invalid mode" end
    if id < 0 and requestedMode and requestedMode ~= "cooldown" then return false, "items only support cooldown mode" end
    for _, e in ipairs(bar.entries) do if e.spellID == id then return false, "duplicate spell" end end
    if slotCount(bar) >= bar.rows * bar.columns then return false, "bar is at capacity" end
    local entry = entryDefaults(id, requestedMode)
    entry.uid = profile.nextEntryID
    profile.nextEntryID = entry.uid + 1
    bar.entries[#bar.entries + 1] = entry
    changed()
    return true, nil, #bar.entries
end

function API.RemoveEntry(barID, index)
    local bar, i = getBar(barID), tonumber(index)
    if not bar then return false, "bar not found" end
    if not i or not bar.entries[i] then return false, "entry not found" end
    local uid = bar.entries[i].uid
    table.remove(bar.entries, i)
    entryRuntime[uid] = nil
    normalizeCombined(bar)
    changed()
    return true
end

function API.MoveEntry(barID, index, destination)
    local bar, from, to = getBar(barID), tonumber(index), tonumber(destination)
    if not bar then return false, "bar not found" end
    if not from or not bar.entries[from] then return false, "entry not found" end
    if to == -1 or to == 1 then to = from + to end
    if not to or not bar.entries[to] then return false, "destination not found" end
    local original, flags = {}, {}
    for position, current in ipairs(bar.entries) do original[position], flags[current] = current, current.combined end
    local entry = table.remove(bar.entries, from)
    table.insert(bar.entries, to, entry)
    normalizeCombined(bar)
    if slotCount(bar) > bar.rows * bar.columns then
        bar.entries = original
        for current, combined in pairs(flags) do current.combined = combined end
        return false, "move would exceed bar capacity"
    end
    changed()
    return true
end

function API.SetEntryCombined(barID, index, combined)
    local bar, i = getBar(barID), tonumber(index)
    if not bar or not i or not bar.entries[i] then return false, "entry not found" end
    if i == 1 and combined then return false, "first entry cannot be combined" end
    local old = bar.entries[i].combined
    bar.entries[i].combined = combined and true or false
    if slotCount(bar) > bar.rows * bar.columns then bar.entries[i].combined = old return false, "bar is at capacity" end
    changed()
    return true
end

function API.SetEntryOption(barID, index, key, value)
    local bar, i = getBar(barID), tonumber(index)
    local entry = bar and bar.entries[i or 0]
    if not entry then return false, "entry not found" end
    if key == "combined" then return API.SetEntryCombined(barID, i, value) end
    if key == "mode" then
        if not MODES[value] then return false, "invalid mode" end
        if entry.spellID < 0 and value ~= "cooldown" then return false, "items only support cooldown mode" end
        if value == "reactive" and not entry.reactive then
            local cat = catalogFor(entry.spellID)
            if not (cat and cat.reactive) then return false, "this spell has no reactive trigger preset" end
        end
    elseif key == "readyVisibility" then if not READY[value] then return false, "invalid ready visibility" end
    elseif key == "inactiveVisibility" then if not INACTIVE[value] then return false, "invalid inactive visibility" end
    elseif key == "duration" then
        if value ~= nil then value = tonumber(value) if not value or value <= 0 then return false, "duration must be positive or nil" end end
    elseif key == "learnedDuration" then
        if value ~= nil then value = tonumber(value) if not value or value <= 0 then return false, "learned duration must be positive or nil" end end
    elseif key == "auraID" then
        if value ~= nil then value = tonumber(value) if not value or value <= 0 then return false, "invalid aura ID" end end
    elseif key == "reactive" then if value ~= nil and value ~= "riposte" and value ~= "surprise" then return false, "invalid reactive kind" end
    else return false, "unknown entry option" end
    entry[key] = value
    if key == "mode" and value == "reactive" and not entry.reactive then
        local cat = catalogFor(entry.spellID)
        entry.reactive = cat and cat.reactive or nil
    end
    entryRuntime[entry.uid] = nil
    changed()
    return true
end

function API.ClearBar(id)
    local bar = getBar(id)
    if not bar then return false, "bar not found" end
    for _, e in ipairs(bar.entries) do entryRuntime[e.uid] = nil end
    bar.entries = {}
    changed()
    return true
end

function API.Resolve(value) return resolveSpell(value) end
function API.SpellName(id) return spellName(id) end
function API.SpellIcon(id) return spellIcon(id) end
function API.Rank(id) return ranks[id] end
function API.SpellRank(id) return ranks[id] end
function API.RankNumber(id) return rankNumber(id) end
function API.Refresh() refreshAll() end
function API.Persist() refreshAll() configChanged() end

function API.ProfileNames()
    local names = {}
    for name in pairs(db.profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end
function API.ActiveProfile() return activeProfileName() end

function API.Profile(action, name)
    action, name = string.lower(trim(action)), trim(name)
    local active = activeProfileName()
    if action == "" or action == "list" then return true, API.ProfileNames() end
    if InCombatLockdown and InCombatLockdown() then return false, "profiles cannot change in combat" end
    if name == "" or #name > 48 or name:find("[%c|]") then return false, "invalid profile name" end
    for _, oldBar in ipairs(profile.bars) do stopDrag(oldBar) end
    if action == "new" or action == "copy" or action == "rename" then
        if db.profiles[name] then return false, "profile already exists" end
        if action == "new" then db.profiles[name] = freshProfile() else db.profiles[name] = cloneProfile(profile) end
        if action == "rename" then
            db.profiles[active] = nil
            for guid, pname in pairs(db.profileKeys) do if pname == active then db.profileKeys[guid] = name end end
        else db.profileKeys[playerGUID()] = name end
        profile = db.profiles[name]
    elseif action == "use" then
        if not db.profiles[name] then return false, "profile not found" end
        db.profileKeys[playerGUID()] = name
        profile = db.profiles[name]
    elseif action == "delete" then
        if not db.profiles[name] then return false, "profile not found" end
        if name == active then return false, "active profile cannot be deleted" end
        for _, pname in pairs(db.profileKeys) do if pname == name then return false, "profile is used by a character" end end
        db.profiles[name] = nil
    else return false, "unknown profile action" end
    if action ~= "delete" then
        profile = normalizeProfile(profile)
        runtimeGeneration = runtimeGeneration + 1
        entryRuntime = {}
        for _, row in pairs(rows) do row.positioned = false end
    end
    changed()
    return true
end

function API.Auto(barID)
    local bar = getBar(barID)
    if not bar then return 0, "bar not found" end
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return 0, "spellbook unavailable" end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local added = 0
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if not secret(info) and not secretTable(info) and type(info) == "table" then
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                if not secret(item) and not secretTable(item) and type(item) == "table" then
                    local spellID = item.spellID
                    local passive = secret(item.isPassive) and true or item.isPassive
                    local offSpec = secret(item.isOffSpec) and true or item.isOffSpec
                    if type(spellID) == "number" and not secret(spellID) and not passive and not offSpec
                        and slotCount(bar) < bar.rows * bar.columns then
                    local duplicate, highest = false, true
                    for _, e in ipairs(bar.entries) do if e.spellID == spellID then duplicate = true end end
                    for _, sid in ipairs(siblings[spellID] or {}) do if rankNumber(sid) > rankNumber(spellID) then highest = false end end
                    if not duplicate and highest then
                        local c = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
                        local charges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
                        local has = type(c) == "table" and not secret(c) and not secretTable(c)
                            and not secret(c.duration) and (c.duration or 0) > 1.5
                        if type(charges) == "table" and not secret(charges) and not secretTable(charges)
                            and not secret(charges.cooldownDuration) and (charges.cooldownDuration or 0) > 1.5 then has = true end
                        if not has and GetSpellBaseCooldown then
                            local ok, milliseconds = pcall(GetSpellBaseCooldown, spellID)
                            if ok and not secret(milliseconds) and type(milliseconds) == "number" and milliseconds > 1500 then has = true end
                        end
                        if not has and C_Spell.GetSpellDescription then
                            local description = C_Spell.GetSpellDescription(spellID)
                            if type(description) == "string" and not secret(description) then
                                has = string.lower(description):find("cooldown", 1, true) ~= nil
                            end
                        end
                        if has then
                            local e = entryDefaults(spellID)
                            e.uid, profile.nextEntryID = profile.nextEntryID, profile.nextEntryID + 1
                            bar.entries[#bar.entries + 1] = e
                            added = added + 1
                        end
                    end
                    end
                end
            end
        end
    end
    if added > 0 then changed() end
    return added
end

function API.ActivateReactive(kind, targetGUID)
    if kind ~= "riposte" and kind ~= "surprise" then return false, "invalid reactive kind" end
    local now, activated = GetTime(), 0
    for _, bar in ipairs(profile.bars) do
        for _, entry in ipairs(bar.entries) do
            if entry.mode == "reactive" and entry.reactive == kind then
                local rt = entryRuntime[entry.uid] or {}
                entryRuntime[entry.uid] = rt
                if not (rt.consumedAt and now - rt.consumedAt <= 0.5)
                    and not (rt.lastTriggerAt and now - rt.lastTriggerAt <= 0.5) then
                    rt.procAt, rt.procUntil = now, now + (catalogDuration(entry) or 4)
                    rt.lastTriggerAt = now
                    rt.targetGUID = kind == "surprise" and targetGUID or nil
                    activated = activated + 1
                elseif kind == "surprise" and not rt.targetGUID then
                    rt.targetGUID = targetGUID
                end
            end
        end
    end
    if activated > 0 then refreshAll() end
    return activated > 0, activated
end

function API.SetLocked(locked)
    db.settings.locked = locked and true or false
    updateInteractions(true)
    configChanged()
    return true
end
ForeverCDMAdvanced_SetLocked = API.SetLocked

-- Events ---------------------------------------------------------------------

local function castMatches(entry, spellID, name)
    if entry.spellID == spellID or entry.auraID == spellID then return true end
    return spellName(entry.spellID) == name
end

local function onPlayerCast(unit, _, spellID)
    if unit ~= "player" or secret(spellID) or type(spellID) ~= "number" then return end
    local name, target = spellName(spellID), currentTargetGUID()
    for _, bar in ipairs(profile.bars) do
        for _, entry in ipairs(bar.entries) do
            if castMatches(entry, spellID, name) then
                local rt = entryRuntime[entry.uid] or {}
                entryRuntime[entry.uid] = rt
                if entry.mode == "aura" or entry.mode == "debuff" or entry.mode == "auraCooldown" then
                    rt.castAt = GetTime()
                    if entry.mode == "debuff" and target then
                        rt.casts = rt.casts or {}
                        rt.casts[target] = {at=rt.castAt, spellID=spellID}
                    end
                elseif entry.mode == "reactive" and rt.procUntil and GetTime() < rt.procUntil then
                    if entry.reactive ~= "surprise" or not rt.targetGUID or target == nil or rt.targetGUID == target then
                        rt.latched = true
                        rt.latchedAt = GetTime()
                        rt.consumedAt = rt.latchedAt
                        rt.procAt, rt.procUntil = nil, nil
                    end
                end
            end
        end
    end
    refreshAll()
end

local function onAuraEvent(unit, info)
    if type(info) ~= "table" or secret(info) or secretTable(info) then return end
    local removed = info.removedAuraInstanceIDs
    local readableRemoved = type(removed) == "table" and not secret(removed) and not secretTable(removed)
    for _, bar in ipairs(profile.bars) do
        for _, entry in ipairs(bar.entries) do
            local watchesUnit = unit == "target" and entry.mode == "debuff"
                or unit == "player" and (entry.mode == "aura" or entry.mode == "auraCooldown")
            local runtime = watchesUnit and entryRuntime[entry.uid]
            if runtime and readableRemoved and runtime.auraInstanceID then
                for _, instanceID in ipairs(removed) do
                    if not secret(instanceID) and instanceID == runtime.auraInstanceID then
                        runtime.knownActive, runtime.auraInstanceID, runtime.knownExpires = nil, nil, nil
                        runtime.knownTargetGUID = nil
                        break
                    end
                end
            end
        end
    end
end

local function onUnitCombat(unit, result)
    if secret(result) or type(result) ~= "string" then return end
    if unit == "player" and result == "PARRY" then API.ActivateReactive("riposte")
    elseif unit == "target" and result == "DODGE" then
        local target = currentTargetGUID()
        if target then API.ActivateReactive("surprise", target) end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if db then refreshAll() end
    elseif event == "PLAYER_LOGIN" then
        ensureDB()
        inCombat = InCombatLockdown and InCombatLockdown() and true or false
        buildRankIndex()
        refreshAll()
        initEditMode()
        configChanged()
        for _, name in ipairs({"SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED",
            "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
            "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED"}) do
            self:RegisterEvent(name)
        end
        self:RegisterUnitEvent("UNIT_AURA", "player", "target")
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
        if ForeverCDMAdvanced_InitMinimap then ForeverCDMAdvanced_InitMinimap() end
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
        say("v%s loaded. /fcdma opens settings.", tostring(version))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then onPlayerCast(...)
    elseif event == "UNIT_AURA" then onAuraEvent(...) refreshAll()
    elseif event == "UNIT_COMBAT" then onUnitCombat(...)
    elseif event == "PLAYER_REGEN_DISABLED" then inCombat = true updateInteractions(true)
    elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false updateInteractions(false)
    elseif event == "SPELLS_CHANGED" then buildRankIndex() refreshAll() configChanged()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if itemNamesPending then itemNamesPending = false refreshAll() configChanged() end
    else refreshAll() end
end)

if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.25, function() if db and #profile.bars > 0 then refreshAll() end end) end

-- Slash commands --------------------------------------------------------------

local HELP = {
    "/fcdma  open settings",
    "/fcdma profile [list|new|copy|use|rename|delete] <name>",
    "/fcdma bar new <name> | delete <id> | rename <id> <name> | list",
    "/fcdma add <barID> <spell> | remove <barID> <index|spell>",
    "/fcdma mode <barID> <index> <cooldown|aura|debuff|auraCooldown|reactive>",
    "/fcdma grid <barID> <rows> <columns> | grow <barID> <left|right> <up|down>",
    "/fcdma size <barID> <pixels> | spacing <barID> <pixels>",
    "/fcdma anchor <barID> <otherBarID|FrameName|none>",
    "/fcdma duration <barID> <index> <seconds|auto>",
    "/fcdma lock | unlock | fade show|fade|hide | names on|off | minimap",
    "/fcdma reset  replace schema v2 with a fresh zero-bar database",
}

local function listBars()
    if #profile.bars == 0 then say("no bars") return end
    for _, bar in ipairs(profile.bars) do say("%d: %s (%d/%d slots)", bar.id, bar.name, slotCount(bar), bar.rows * bar.columns) end
end

SLASH_FOREVERCDMADVANCED1 = "/fcdma"
SlashCmdList.FOREVERCDMADVANCED = function(message)
    if not db then say("not loaded yet") return end
    local cmd, rest = trim(message):match("^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")
    if cmd == "" or cmd == "config" or cmd == "options" then
        if ForeverCDMAdvanced_ToggleConfig then ForeverCDMAdvanced_ToggleConfig() else say("config window unavailable") end
    elseif cmd == "profile" then
        local action, name = rest:match("^(%S*)%s*(.-)$")
        local ok, reason = API.Profile(action, name)
        if not ok then say("%s", reason) elseif string.lower(action or "") == "list" or action == "" then say("active: %s; available: %s", activeProfileName(), table.concat(API.ProfileNames(), ", ")) end
    elseif cmd == "bar" then
        local action, tail = rest:match("^(%S*)%s*(.-)$")
        action = string.lower(action or "")
        if action == "new" then
            local id, why = API.CreateBar(tail)
            if id then say("created bar %d", id) else say("%s", why) end
        elseif action == "delete" then local ok, why = API.DeleteBar(tail) if not ok then say("%s", why) end
        elseif action == "rename" then local id, name = tail:match("^(%d+)%s+(.+)$") local ok, why = API.RenameBar(id, name) if not ok then say("%s", why) end
        elseif action == "list" then listBars() else say("usage: /fcdma bar new|delete|rename|list") end
    elseif cmd == "add" then
        local id, spell = rest:match("^(%d+)%s+(.+)$")
        local ok, why = API.AddEntry(id, spell)
        if not ok then say("%s", why) end
    elseif cmd == "remove" then
        local id, value = rest:match("^(%d+)%s+(.+)$")
        local bar, index = getBar(id), tonumber(value)
        if bar and (not index or not bar.entries[index]) then
            local spell = resolveSpell(value)
            for i, entry in ipairs(bar.entries) do if entry.spellID == spell then index = i break end end
        end
        local ok, why = API.RemoveEntry(id, index)
        if not ok then say("%s", why) end
    elseif cmd == "mode" then
        local id, index, mode = rest:match("^(%d+)%s+(%d+)%s+(%S+)$")
        if mode and string.lower(mode) == "auracooldown" then mode = "auraCooldown" else mode = mode and string.lower(mode) end
        local ok, why = API.SetEntryOption(id, index, "mode", mode)
        if not ok then say("%s", why) end
    elseif cmd == "grid" then
        local id, r, c = rest:match("^(%d+)%s+(%d+)%s+(%d+)$")
        local bar = getBar(id)
        r, c = tonumber(r), tonumber(c)
        if not bar or not r or not c or r < 1 or r > 20 or c < 1 or c > 20 then say("usage: /fcdma grid <barID> <rows 1-20> <columns 1-20>")
        elseif r * c < slotCount(bar) then say("grid is smaller than the used visual slots")
        else bar.rows, bar.columns = r, c changed() end
    elseif cmd == "grow" then
        local id, x, y = rest:match("^(%d+)%s+(%a+)%s+(%a+)$")
        local ok, why = API.SetBarOption(id, "growX", x)
        if ok then ok, why = API.SetBarOption(id, "growY", y) end
        if not ok then say("%s", why) end
    elseif cmd == "size" or cmd == "spacing" then
        local id, value = rest:match("^(%d+)%s+(%-?%d+)$")
        local ok, why = API.SetBarOption(id, cmd, value)
        if not ok then say("%s", why) end
    elseif cmd == "anchor" then
        local id, target = rest:match("^(%d+)%s+(%S+)$")
        local value = target == "none" and nil or tonumber(target) or target
        local ok, why = API.SetBarOption(id, "anchor", value)
        if not ok then say("%s", why) end
    elseif cmd == "duration" then
        local id, index, value = rest:match("^(%d+)%s+(%d+)%s+(%S+)$")
        local duration = value ~= "auto" and value or nil
        local ok, why = API.SetEntryOption(id, index, "duration", duration)
        if not ok then say("%s", why) end
    elseif cmd == "lock" or cmd == "unlock" then API.SetLocked(cmd == "lock")
    elseif cmd == "fade" then
        local value = string.lower(rest)
        if value ~= "show" and value ~= "fade" and value ~= "hide" then say("usage: /fcdma fade show|fade|hide")
        else db.settings.fade = value == "show" and nil or value changed() end
    elseif cmd == "names" then db.settings.showNames = rest == "on" changed()
    elseif cmd == "minimap" then
        if ForeverCDMAdvanced_SetMinimapShown then ForeverCDMAdvanced_SetMinimapShown(db.settings.minimap.hide) configChanged() end
    elseif cmd == "reset" then
        for _, oldBar in ipairs(profile.bars) do stopDrag(oldBar) end
        for id, row in pairs(rows) do
            row.positioned, row.pendingAnchor, row.dragging = false, nil, nil
            row:Hide()
            for _, icon in ipairs(icons[id] or {}) do
                icon.appearanceSignature = nil
                icon.cooldownUID, icon.auraUID, icon.uid, icon.callbackGeneration = nil, nil, nil, nil
                clearCooldown(icon)
                resetIconTransient(icon)
                resetTracker(icon)
                icon:Hide()
            end
        end
        ForeverCDMAdvancedDB = freshDB()
        db = ForeverCDMAdvancedDB
        selectCharacterProfile()
        runtimeGeneration = runtimeGeneration + 1
        entryRuntime = {}
        changed()
        if ForeverCDMAdvanced_InitMinimap then ForeverCDMAdvanced_InitMinimap() end
        say("reset complete; active profile has zero bars")
    elseif cmd == "probe" then
        local id = resolveSpell(rest)
        if not id then say("usage: /fcdma probe <spell>") else
            local aura, readable = auraForPlayer(id)
            local c = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
            say("%s (%d): aura=%s readable=%s cooldown=%s", spellName(id), id, aura and "present" or "absent", tostring(readable), c and "available" or "unavailable")
        end
    else
        say("commands:")
        for _, line in ipairs(HELP) do print("   " .. line) end
    end
end
