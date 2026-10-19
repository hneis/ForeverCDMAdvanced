-- ForeverCDMAdvanced_UI.lua -- dynamic bar settings and minimap button.
-- Plain frames only: this keeps the window independent of Blizzard templates.

local CDM = ForeverCDMAdvanced
local win

local ICON_PATH = "Interface\\AddOns\\ForeverCDMAdvanced\\media\\icon.tga"
local BG      = { 0.055, 0.055, 0.065 }
local CARD    = { 0.090, 0.090, 0.105 }
local LINE    = { 0.200, 0.200, 0.230 }
local BTN     = { 0.150, 0.150, 0.175 }
local BTN_HI  = { 0.220, 0.220, 0.255 }
local ACCENT  = { 0.824, 0.384, 0.122 }
local DIM     = { 0.600, 0.600, 0.640 }
local ROW_H, HEAD_H = 24, 22

local selectedBarID, selectedEntry, selectedProfileName
local draggedSpell
local spellRows, spellHeads, barRows, entryRows = {}, {}, {}, {}
local refreshUI

local function secret(value) return issecretvalue and issecretvalue(value) end
local function secretTable(value) return issecrettable and issecrettable(value) end

local function db()
    return CDM.GetDB()
end

local function settings()
    return db().settings
end

local function fill(frame, layer, color, alpha)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return texture
end

local function outline(frame, color, alpha)
    local function strip(first, second, horizontal)
        local texture = frame:CreateTexture(nil, "BORDER")
        texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
        texture:SetPoint(first)
        texture:SetPoint(second)
        if horizontal then texture:SetHeight(1) else texture:SetWidth(1) end
    end
    strip("TOPLEFT", "TOPRIGHT", true)
    strip("BOTTOMLEFT", "BOTTOMRIGHT", true)
    strip("TOPLEFT", "BOTTOMLEFT", false)
    strip("TOPRIGHT", "BOTTOMRIGHT", false)
end

local function text(parent, font, value, color)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    if value then label:SetText(value) end
    if color then label:SetTextColor(color[1], color[2], color[3]) end
    return label
end

local function paint(button)
    local color = button.active and ACCENT or (button.hover and BTN_HI or BTN)
    button.bg:SetColorTexture(color[1], color[2], color[3], 1)
end

local function flatButton(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height or 22)
    button.bg = fill(button, "BACKGROUND", BTN)
    outline(button, LINE)
    button.label = text(button, "GameFontHighlightSmall", label)
    button.label:SetPoint("CENTER")
    button:SetFontString(button.label)
    button:SetScript("OnEnter", function(self) self.hover = true paint(self) end)
    button:SetScript("OnLeave", function(self) self.hover = false paint(self) end)
    button:SetScript("OnDisable", function(self) self.label:SetTextColor(0.35, 0.35, 0.38) end)
    button:SetScript("OnEnable", function(self) self.label:SetTextColor(1, 1, 1) end)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

local function setActive(button, active)
    button.active = active and true or false
    paint(button)
end

local function checkbox(parent, label, onClick)
    local check = CreateFrame("CheckButton", nil, parent)
    check:SetSize(16, 16)
    fill(check, "BACKGROUND", BG)
    outline(check, LINE)
    local mark = check:CreateTexture(nil, "ARTWORK")
    mark:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    check:SetCheckedTexture(mark)
    if label then
        check.label = text(parent, "GameFontHighlightSmall", label)
        check.label:SetPoint("LEFT", check, "RIGHT", 7, 0)
    end
    if onClick then check:SetScript("OnClick", onClick) end
    return check
end

local function editBox(parent, name, width, height)
    local box = CreateFrame("EditBox", name, parent)
    box:SetSize(width, height or 22)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    fill(box, "BACKGROUND", BG)
    outline(box, LINE)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function card(parent, title, x, width, top, bottom)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", x, top)
    frame:SetPoint("BOTTOMLEFT", x, bottom)
    frame:SetWidth(width)
    fill(frame, "BACKGROUND", CARD)
    outline(frame, LINE)
    frame.title = text(frame, "GameFontNormalSmall", title, ACCENT)
    frame.title:SetPoint("TOPLEFT", 10, -9)
    return frame
end

local function scrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(10, 1)
    scroll:SetScrollChild(content)
    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
    thumb:SetWidth(3)
    local function update()
        local range = scroll:GetVerticalScrollRange() or 0
        local height = scroll:GetHeight() or 1
        if range <= 0.5 then thumb:Hide() return end
        local thumbHeight = math.max(24, height * height / (height + range))
        local position = (scroll:GetVerticalScroll() / range) * (height - thumbHeight)
        thumb:SetHeight(thumbHeight)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -position)
        thumb:Show()
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48)))
        update()
    end)
    scroll:SetScript("OnScrollRangeChanged", function(self, _, range)
        if self:GetVerticalScroll() > (range or 0) then self:SetVerticalScroll(range or 0) end
        update()
    end)
    return scroll, content
end

local function notice(message)
    print("|cffd2621fForever CDM Advanced|r: " .. tostring(message))
end

local function changed()
    CDM.Refresh()
    CDM.Persist()
    if refreshUI then refreshUI() end
end

local function rejected(reason, fallback)
    notice(reason and tostring(reason) or fallback or "That change was rejected.")
end

local function bars()
    return CDM.GetBars() or {}
end

local function currentBar()
    if selectedBarID ~= nil then
        local bar = CDM.GetBar(selectedBarID)
        if bar then return bar end
    end
    selectedBarID = nil
    selectedEntry = nil
    local list = bars()
    if list[1] then
        selectedBarID = list[1].id
        return CDM.GetBar(selectedBarID) or list[1]
    end
end

local function nameWithRank(id, name)
    local rank = CDM.Rank(id)
    return rank and rank ~= "" and (name .. "  |cff8c8c96" .. rank .. "|r") or name
end

local function trackedIDs(out, seen)
    for _, bar in ipairs(bars()) do
        for _, entry in ipairs(bar.entries or {}) do
            local id = entry.spellID
            if id and not seen[id] then
                seen[id] = true
                out[#out + 1] = { id = id, name = CDM.SpellName(id), tab = id < 0 and "Items" or "Tracked" }
            end
        end
    end
end

local function spellbookSpells()
    local out, seen = {}, {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if not secret(info) and not secretTable(info) and type(info) == "table" then
                for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                    if not secret(item) and not secretTable(item) and type(item) == "table" then
                        local spellID = item.spellID
                        local passive = secret(item.isPassive) and true or item.isPassive
                        local offSpec = secret(item.isOffSpec) and true or item.isOffSpec
                        if type(spellID) == "number" and not secret(spellID) and not passive and not offSpec and not seen[spellID] then
                        seen[spellID] = true
                        out[#out + 1] = {
                            id = spellID,
                            name = type(item.name) == "string" and not secret(item.name) and item.name or CDM.SpellName(spellID),
                            tab = type(info.name) == "string" and not secret(info.name) and info.name or "Other",
                        }
                        end
                    end
                end
            end
        end
    end

    local ammoClass = Enum and Enum.ItemClass and Enum.ItemClass.Projectile or 6
    local function isAmmo(itemID)
        return C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(itemID)) == ammoClass
    end
    local function offerItem(itemID)
        local id = itemID and -itemID
        if id and not seen[id] and C_Item and ((C_Item.GetItemSpell and C_Item.GetItemSpell(itemID)) or isAmmo(itemID)) then
            seen[id] = true
            out[#out + 1] = { id = id, name = CDM.SpellName(id), tab = "Items" }
        end
    end
    if GetInventoryItemID then
        for slot = 0, 19 do offerItem(GetInventoryItemID("player", slot)) end
    end
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                offerItem(C_Container.GetContainerItemID(bag, slot))
            end
        end
    end
    trackedIDs(out, seen)
    table.sort(out, function(a, b)
        if a.tab ~= b.tab then return a.tab < b.tab end
        if a.name ~= b.name then return a.name < b.name end
        local rankA, rankB = CDM.RankNumber(a.id) or 0, CDM.RankNumber(b.id) or 0
        if rankA ~= rankB then return rankA < rankB end
        return a.id < b.id
    end)
    return out
end

local function addEntry(value)
    local bar = currentBar()
    if not bar then rejected(nil, "Create or select a bar first.") return end
    if value == nil or value == "" then rejected(nil, "Enter a spell name, spell ID, or item link.") return end
    local ok, reason, index = CDM.AddEntry(bar.id, value)
    if not ok then rejected(reason, "Could not add that entry.") return end
    selectedEntry = index or #(CDM.GetBar(bar.id).entries or {})
    if win and win.addBox then win.addBox:SetText("") win.addBox:ClearFocus() end
    changed()
end

local function setBarOption(key, value)
    local bar = currentBar()
    if not bar then return end
    local ok, reason = CDM.SetBarOption(bar.id, key, value)
    if not ok then rejected(reason, "Bar capacity or value limit reached.") return end
    changed()
end

local function setEntryOption(key, value)
    local bar = currentBar()
    if not bar or not selectedEntry or not bar.entries[selectedEntry] then return end
    local ok, reason = CDM.SetEntryOption(bar.id, selectedEntry, key, value)
    if ok == false then rejected(reason, "That entry option was rejected.") return end
    changed()
end

local function cycle(value, choices)
    for index, choice in ipairs(choices) do
        if choice == value then return choices[index % #choices + 1] end
    end
    return choices[1]
end

local function mouseIsOver(frame)
    if not (frame and GetMouseFoci) then return false end
    local foci = GetMouseFoci()
    if DoesAncestryIncludeAny then return DoesAncestryIncludeAny(frame, foci) end
    for _, focus in ipairs(foci or {}) do
        local current = focus
        while current do
            if current == frame then return true end
            current = current.GetParent and current:GetParent() or nil
        end
    end
    return false
end

local function nextMode(entry)
    if entry.spellID < 0 then return "cooldown" end
    local choices = {"cooldown", "aura", "debuff", "auraCooldown"}
    if entry.reactive then choices[#choices + 1] = "reactive" end
    return cycle(entry.mode, choices)
end

local function newSpellRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    row.hover = fill(row, "BACKGROUND", BTN_HI, 0.35)
    row.hover:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = text(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -45, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.add = flatButton(row, "Add", 38, 20, function(self) addEntry(self:GetParent().id) end)
    row.add:SetPoint("RIGHT", -3, 0)
    row:SetScript("OnEnter", function(self)
        self.hover:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.id < 0 then GameTooltip:SetItemByID(-self.id) else GameTooltip:SetSpellByID(self.id) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() GameTooltip:Hide() end)
    row:SetScript("OnDragStart", function(self)
        draggedSpell = self.id
        if SetCursor then SetCursor("CAST_CURSOR") end
    end)
    row:SetScript("OnDragStop", function()
        local value = draggedSpell
        draggedSpell = nil
        if ResetCursor then ResetCursor() end
        if value and win and win.dropZone and mouseIsOver(win.dropZone) then addEntry(value) end
    end)
    return row
end

local function refreshSpellbook()
    local spells = spellbookSpells()
    local content = win.spellContent
    local y, headingCount, lastTab = 0, 0, nil
    for index, spell in ipairs(spells) do
        if spell.tab ~= lastTab then
            lastTab = spell.tab
            headingCount = headingCount + 1
            local heading = spellHeads[headingCount]
            if not heading then
                heading = CreateFrame("Frame", nil, content)
                heading:SetHeight(HEAD_H)
                heading.label = text(heading, "GameFontNormalSmall", nil, DIM)
                heading.label:SetPoint("BOTTOMLEFT", 6, 4)
                heading.rule = heading:CreateTexture(nil, "ARTWORK")
                heading.rule:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
                heading.rule:SetHeight(1)
                heading.rule:SetPoint("BOTTOMLEFT", 4, 0)
                heading.rule:SetPoint("BOTTOMRIGHT", -4, 0)
                spellHeads[headingCount] = heading
            end
            heading.label:SetText(string.upper(spell.tab))
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            heading:SetPoint("RIGHT", content, "RIGHT")
            heading:Show()
            y = y + HEAD_H
        end
        local row = spellRows[index]
        if not row then row = newSpellRow(content) spellRows[index] = row end
        row.id = spell.id
        row.icon:SetTexture(CDM.SpellIcon(spell.id))
        row.name:SetText(nameWithRank(spell.id, spell.name))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", content, "RIGHT")
        row:Show()
        y = y + ROW_H
    end
    for index = #spells + 1, #spellRows do spellRows[index]:Hide() end
    for index = headingCount + 1, #spellHeads do spellHeads[index]:Hide() end
    content:SetHeight(math.max(y, 1))
end

local function refreshBars()
    local list = bars()
    local valid = false
    for _, bar in ipairs(list) do if bar.id == selectedBarID then valid = true break end end
    if not valid then
        selectedBarID = list[1] and list[1].id or nil
        selectedEntry = nil
    end
    for index, bar in ipairs(list) do
        local row = barRows[index]
        if not row then
            row = flatButton(win.barContent, "", 164, 24, function(self)
                selectedBarID = self.barID
                selectedEntry = nil
                refreshUI()
            end)
            row.label:SetPoint("LEFT", 7, 0)
            row.label:SetPoint("RIGHT", -7, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(false)
            barRows[index] = row
        end
        row.barID = bar.id
        row:SetText(bar.name or tostring(bar.id))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * 27)
        row:SetPoint("RIGHT", win.barContent, "RIGHT")
        setActive(row, bar.id == selectedBarID)
        row:Show()
    end
    for index = #list + 1, #barRows do barRows[index]:Hide() end
    win.barContent:SetHeight(math.max(#list * 27, 1))
    win.noBars:SetShown(#list == 0)
end

local modeNames = {
    cooldown = "CD", aura = "AURA", debuff = "DEBUFF", auraCooldown = "AURA+CD", reactive = "REACTIVE",
}

local function refreshEntries(bar)
    local entries = bar and bar.entries or {}
    if selectedEntry and not entries[selectedEntry] then selectedEntry = nil end
    for index, entry in ipairs(entries) do
        local row = entryRows[index]
        if not row then
            row = CreateFrame("Button", nil, win.entryContent)
            row:SetHeight(ROW_H)
            row.bg = fill(row, "BACKGROUND", BG, 0.55)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(19, 19)
            row.icon:SetPoint("LEFT", 5, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.name = text(row, "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetPoint("RIGHT", -66, 0)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.mode = text(row, "GameFontNormalSmall", nil, DIM)
            row.mode:SetPoint("RIGHT", -5, 0)
            row:SetScript("OnClick", function(self) selectedEntry = self.index refreshUI() end)
            entryRows[index] = row
        end
        row.index = index
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", entry.combined and index > 1 and 17 or 5, 0)
        row.icon:SetTexture(CDM.SpellIcon(entry.spellID))
        row.name:SetText(nameWithRank(entry.spellID, CDM.SpellName(entry.spellID)))
        row.mode:SetText(modeNames[entry.mode] or tostring(entry.mode or ""))
        local color = index == selectedEntry and ACCENT or BG
        row.bg:SetColorTexture(color[1], color[2], color[3], index == selectedEntry and 0.75 or 0.55)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
        row:SetPoint("RIGHT", win.entryContent, "RIGHT")
        row:Show()
    end
    for index = #entries + 1, #entryRows do entryRows[index]:Hide() end
    win.entryContent:SetHeight(math.max(#entries * ROW_H, 1))
    win.emptyEntries:SetShown(bar ~= nil and #entries == 0)
    win.noSelection:SetShown(bar == nil)
end

local function setControlEnabled(control, enabled)
    control:SetEnabled(enabled)
    if control.label then control.label:SetTextColor(enabled and 1 or 0.4, enabled and 1 or 0.4, enabled and 1 or 0.42) end
end

local borderModeNames = { none = "None", solid = "Solid", eui = "EUI sync" }
local fontFaceNames = { ellesmere = "EUI", friz = "Friz", arial = "Arial", skurri = "Skurri", morpheus = "Morpheus" }
local fontOutlineNames = { NONE = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick" }

local function colorComponents(color, defaultR, defaultG, defaultB, defaultA)
    color = type(color) == "table" and color or {}
    return tonumber(color.r or color[1]) or defaultR,
        tonumber(color.g or color[2]) or defaultG,
        tonumber(color.b or color[3]) or defaultB,
        tonumber(color.a or color[4]) or defaultA
end

local function pickerColor(alpha, modern)
    local r, g, b = ColorPickerFrame:GetColorRGB()
    if modern and ColorPickerFrame.GetColorAlpha then
        local ok, value = pcall(ColorPickerFrame.GetColorAlpha, ColorPickerFrame)
        if ok and type(value) == "number" then alpha = value end
    elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
        alpha = 1 - OpacitySliderFrame:GetValue()
    end
    return r, g, b, alpha
end

local function openBarColorPicker(key, defaults)
    local bar = currentBar()
    if not bar or not ColorPickerFrame then return end
    local barID = bar.id
    local r, g, b, a = colorComponents(bar[key], defaults[1], defaults[2], defaults[3], defaults[4])
    local original = { r = r, g = g, b = b, a = a }
    local modern = ColorPickerFrame.SetupColorPickerAndShow ~= nil
    local function setColor(color)
        local ok, reason = CDM.SetBarOption(barID, key, color)
        if not ok then rejected(reason, "Color was rejected.") end
        if refreshUI then refreshUI() end
    end
    local function apply()
        local newR, newG, newB, newA = pickerColor(a, modern)
        setColor({ r = newR, g = newG, b = newB, a = newA })
    end
    local function cancel() setColor({ r = original.r, g = original.g, b = original.b, a = original.a }) end
    if modern then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = true,
            swatchFunc = apply, opacityFunc = apply, cancelFunc = cancel,
        })
    else
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = true
        ColorPickerFrame.opacity = 1 - a
        ColorPickerFrame.previousValues = { r = r, g = g, b = b, a = a }
        ColorPickerFrame.func = apply
        ColorPickerFrame.opacityFunc = apply
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end
end

local function setAppearanceStepperEnabled(stepper, enabled)
    setControlEnabled(stepper.minus, enabled)
    setControlEnabled(stepper.plus, enabled)
    stepper.caption:SetTextColor(enabled and DIM[1] or 0.35, enabled and DIM[2] or 0.35, enabled and DIM[3] or 0.37)
    stepper.value:SetTextColor(enabled and 1 or 0.4, enabled and 1 or 0.4, enabled and 1 or 0.42)
end

local function setSwatchEnabled(swatch, enabled)
    swatch:SetEnabled(enabled)
    swatch.caption:SetTextColor(enabled and DIM[1] or 0.35, enabled and DIM[2] or 0.35, enabled and DIM[3] or 0.37)
    swatch.color:SetAlpha(enabled and 1 or 0.35)
end

local function refreshAppearance(bar)
    if not (win and win.appearancePanel) then return end
    local a = win.appearance
    local enabled = bar ~= nil
    local borderMode = bar and bar.borderMode or "none"
    local borderR, borderG, borderB, borderA = colorComponents(bar and bar.borderColor, 0, 0, 0, 1)
    local glowR, glowG, glowB, glowA = colorComponents(bar and bar.procGlowColor, 1, 0.82, 0.1, 1)

    a.title:SetText(bar and ("APPEARANCE  -  " .. tostring(bar.name or bar.id)) or "APPEARANCE  -  NO BAR SELECTED")
    a.borderMode:SetText("Border mode: " .. (borderModeNames[borderMode] or tostring(borderMode)))
    a.borderSource:SetText("EUI source: " .. tostring(bar and bar.borderSource or "MainBar"))
    a.borderSize.value:SetText(bar and tostring(bar.borderSize) or "-")
    a.borderColor.color:SetColorTexture(borderR, borderG, borderB, borderA)
    a.procGlow:SetChecked(bar and bar.procGlowEnabled and true or false)
    a.glowSize.value:SetText(bar and tostring(bar.procGlowSize) or "-")
    a.glowColor.color:SetColorTexture(glowR, glowG, glowB, glowA)
    a.fontFace:SetText("Font face: " .. (fontFaceNames[bar and bar.fontFace] or "-"))
    a.fontSize.value:SetText(bar and tostring(bar.fontSize) or "-")
    a.fontOutline:SetText("Outline: " .. (fontOutlineNames[bar and bar.fontOutline] or "-"))

    setControlEnabled(a.borderMode, enabled)
    a.borderSource:SetShown(enabled and borderMode == "eui")
    a.euiHint:SetShown(enabled and borderMode == "eui")
    setControlEnabled(a.borderSource, enabled and borderMode == "eui")
    setAppearanceStepperEnabled(a.borderSize, enabled and borderMode ~= "eui")
    setSwatchEnabled(a.borderColor, enabled and borderMode ~= "eui")
    a.procGlow:SetEnabled(enabled)
    a.procGlow.label:SetTextColor(enabled and 1 or 0.4, enabled and 1 or 0.4, enabled and 1 or 0.42)
    setAppearanceStepperEnabled(a.glowSize, enabled and bar.procGlowEnabled)
    setSwatchEnabled(a.glowColor, enabled and bar.procGlowEnabled)
    setControlEnabled(a.fontFace, enabled)
    setAppearanceStepperEnabled(a.fontSize, enabled)
    setControlEnabled(a.fontOutline, enabled)
end

refreshUI = function()
    if not win then return end
    local activeProfile = CDM.ActiveProfile()
    if selectedProfileName and selectedProfileName ~= activeProfile then selectedBarID, selectedEntry = nil, nil end
    selectedProfileName = activeProfile
    refreshBars()
    local bar = currentBar()
    refreshEntries(bar)
    refreshSpellbook()

    win.profileButton:SetText("Profile: " .. tostring(activeProfile or "loading..."))
    win.barTitle:SetText(bar and (bar.name or tostring(bar.id)) or "No bar selected")
    win.renameBox:SetText(bar and (bar.name or "") or "")
    win.renameBox:ClearFocus()
    setControlEnabled(win.renameButton, bar ~= nil)
    setControlEnabled(win.deleteButton, bar ~= nil)
    setControlEnabled(win.autoButton, bar ~= nil)
    setControlEnabled(win.clearButton, bar ~= nil)
    setControlEnabled(win.appearanceButton, bar ~= nil)
    refreshAppearance(bar)

    if bar then
        win.sizeValue:SetText(tostring(bar.size))
        win.spacingValue:SetText(tostring(bar.spacing))
        win.rowsValue:SetText(tostring(bar.rows))
        win.columnsValue:SetText(tostring(bar.columns))
        win.growX:SetText("Horizontal: " .. tostring(bar.growX))
        win.growY:SetText("Vertical: " .. tostring(bar.growY))
        win.procMode:SetText("Proc cooldown: " .. tostring(bar.procCooldownMode))
    else
        win.sizeValue:SetText("-")
        win.spacingValue:SetText("-")
        win.rowsValue:SetText("-")
        win.columnsValue:SetText("-")
        win.growX:SetText("Horizontal: -")
        win.growY:SetText("Vertical: -")
        win.procMode:SetText("Proc cooldown: -")
    end

    local entry = bar and selectedEntry and bar.entries[selectedEntry]
    win.entryTitle:SetText(entry and nameWithRank(entry.spellID, CDM.SpellName(entry.spellID)) or "Select an entry")
    win.modeButton:SetText("Mode: " .. (entry and tostring(entry.mode) or "-"))
    win.readyButton:SetText("Ready: " .. (entry and tostring(entry.readyVisibility) or "-"))
    win.inactiveButton:SetText("Inactive: " .. (entry and tostring(entry.inactiveVisibility) or "-"))
    win.durationBox:SetText(entry and (entry.duration == nil and "auto" or tostring(entry.duration)) or "")
    win.combine:SetChecked(entry and selectedEntry > 1 and entry.combined and true or false)
    win.combine:SetEnabled(entry ~= nil and selectedEntry > 1)
    win.upButton:SetEnabled(entry ~= nil and selectedEntry > 1)
    win.downButton:SetEnabled(entry ~= nil and selectedEntry < #bar.entries)
    win.removeButton:SetEnabled(entry ~= nil)
    setControlEnabled(win.modeButton, entry ~= nil)
    setControlEnabled(win.readyButton, entry ~= nil)
    setControlEnabled(win.inactiveButton, entry ~= nil)
    win.durationBox:SetEnabled(entry ~= nil)
    setControlEnabled(win.durationApply, entry ~= nil)

    local s = settings()
    win.names:SetChecked(s.showNames and true or false)
    win.minimap:SetChecked(not s.minimap.hide)
    win.lockButton:SetText(s.locked and "Unlock bars" or "Lock bars")
    setActive(win.lockButton, not s.locked)
    win.fadeButton:SetText("Out of combat: " .. tostring(s.fade or "show"))
end

local function build()
    win = CreateFrame("Frame", "ForeverCDMAdvancedConfig", UIParent)
    win:SetSize(980, 620)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    fill(win, "BACKGROUND", BG, 0.985)
    outline(win, LINE)
    tinsert(UISpecialFrames, "ForeverCDMAdvancedConfig")

    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(40)
    fill(header, "BACKGROUND", CARD)
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    rule:SetHeight(2)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ICON_PATH)
    logo:SetSize(26, 26)
    logo:SetPoint("LEFT", 10, 1)
    local title = text(header, "GameFontNormalLarge", "|cffd2621fForever|r Cooldown Manager", { 1, 1, 1 })
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    local close = flatButton(header, "x", 24, 24, function() win:Hide() end)
    close:SetPoint("RIGHT", -8, 1)

    win.profileButton = flatButton(win, "Profile", 220, 24, function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then
            notice("Use /fcdma profile use <name> to switch profiles.")
            return
        end
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle("Profiles contain all bars and their layout")
            for _, profileName in ipairs(CDM.ProfileNames()) do
                local name = profileName
                root:CreateRadio(name, function() return CDM.ActiveProfile() == name end, function()
                    local ok, reason = CDM.Profile("use", name)
                    if ok then
                        selectedBarID, selectedEntry = nil, nil
                        refreshUI()
                    else
                        rejected(reason, "Could not switch profile.")
                    end
                end)
            end
        end)
    end)
    win.profileButton:SetPoint("TOPLEFT", 14, -50)
    win.profileButton.label:SetWidth(208)
    win.profileButton.label:SetWordWrap(false)
    local profileName = editBox(win, "ForeverCDMAdvancedProfileName", 205, 24)
    profileName:SetPoint("TOPLEFT", 244, -50)
    profileName:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    for index, actionData in ipairs({ { "New", "new" }, { "Copy", "copy" }, { "Rename", "rename" }, { "Delete", "delete" } }) do
        local action = actionData[2]
        local button = flatButton(win, actionData[1], 82, 24, function()
            local ok, reason = CDM.Profile(action, profileName:GetText())
            if ok then
                profileName:SetText("")
                selectedBarID, selectedEntry = nil, nil
            else
                rejected(reason, "Could not change profile.")
            end
            profileName:ClearFocus()
            refreshUI()
        end)
        button:SetPoint("TOPLEFT", 459 + (index - 1) * 88, -50)
    end
    local profileHint = text(win, "GameFontDisableSmall", "The whole bar collection and layout belong to the active profile.")
    profileHint:SetPoint("TOPRIGHT", -16, -79)

    local top, bottom = -94, 38
    local book = card(win, "SPELLBOOK  -  DRAG A ROW OR CLICK ADD", 14, 300, top, bottom)
    local spellScroll, spellContent = scrollArea(book)
    spellScroll:SetPoint("TOPLEFT", 8, -28)
    spellScroll:SetPoint("BOTTOMRIGHT", -8, 8)
    spellContent:SetWidth(278)
    win.spellContent = spellContent

    local barCard = card(win, "BARS", 324, 180, top, bottom)
    local barScroll, barContent = scrollArea(barCard)
    barScroll:SetPoint("TOPLEFT", 8, -28)
    barScroll:SetPoint("BOTTOMRIGHT", -8, 170)
    barContent:SetWidth(158)
    win.barContent = barContent
    win.noBars = text(barCard, "GameFontHighlightSmall", "No bars in this profile.\nCreate one below.", DIM)
    win.noBars:SetPoint("TOPLEFT", 12, -40)
    win.noBars:SetWidth(156)
    win.noBars:SetJustifyH("LEFT")

    local newLabel = text(barCard, "GameFontNormalSmall", "CREATE BAR", ACCENT)
    newLabel:SetPoint("BOTTOMLEFT", 10, 142)
    local newBarBox = editBox(barCard, "ForeverCDMAdvancedNewBarName", 160, 22)
    newBarBox:SetPoint("BOTTOMLEFT", 10, 114)
    local function createBar()
        local name = newBarBox:GetText()
        local id, reason = CDM.CreateBar(name)
        if id == nil then rejected(reason, "Could not create a bar.") return end
        selectedBarID, selectedEntry = id, nil
        newBarBox:SetText("")
        newBarBox:ClearFocus()
        changed()
    end
    newBarBox:SetScript("OnEnterPressed", createBar)
    local createButton = flatButton(barCard, "Create Bar", 160, 22, createBar)
    createButton:SetPoint("BOTTOMLEFT", 10, 86)
    win.renameBox = editBox(barCard, "ForeverCDMAdvancedRenameBar", 160, 22)
    win.renameBox:SetPoint("BOTTOMLEFT", 10, 54)
    local function renameBar()
        local bar = currentBar()
        if not bar then return end
        local ok, reason = CDM.RenameBar(bar.id, win.renameBox:GetText())
        if ok == false then rejected(reason, "Could not rename the bar.") return end
        changed()
    end
    win.renameBox:SetScript("OnEnterPressed", renameBar)
    win.renameButton = flatButton(barCard, "Rename", 77, 22, renameBar)
    win.renameButton:SetPoint("BOTTOMLEFT", 10, 24)
    win.deleteButton = flatButton(barCard, "Delete", 77, 22, function()
        local bar = currentBar()
        if not bar then return end
        CDM.DeleteBar(bar.id)
        selectedBarID, selectedEntry = nil, nil
        changed()
    end)
    win.deleteButton:SetPoint("BOTTOMRIGHT", -10, 24)

    local detail = card(win, "SELECTED BAR", 514, 452, top, bottom)
    win.barTitle = text(detail, "GameFontNormal", "No bar selected")
    win.barTitle:SetPoint("TOPLEFT", 10, -28)
    win.barTitle:SetPoint("RIGHT", -126, 0)
    win.barTitle:SetJustifyH("LEFT")
    win.barTitle:SetWordWrap(false)
    win.appearanceButton = flatButton(detail, "Appearance...", 108, 22, function()
        if currentBar() then
            refreshAppearance(currentBar())
            win.appearanceOverlay:Show()
        end
    end)
    win.appearanceButton:SetPoint("TOPRIGHT", -10, -23)

    win.dropZone = CreateFrame("Frame", nil, detail)
    win.dropZone:SetPoint("TOPLEFT", 8, -50)
    win.dropZone:SetSize(258, 214)
    win.dropZone:EnableMouse(true)
    win.dropZone:RegisterForDrag("LeftButton")
    outline(win.dropZone, LINE)
    local dropHint = text(win.dropZone, "GameFontDisableSmall", "Drop spellbook rows here")
    dropHint:SetPoint("TOP", 0, -5)
    local entryScroll, entryContent = scrollArea(win.dropZone)
    entryScroll:SetPoint("TOPLEFT", 4, -20)
    entryScroll:SetPoint("BOTTOMRIGHT", -4, 4)
    entryContent:SetWidth(244)
    win.entryContent = entryContent
    win.dropZone:SetScript("OnReceiveDrag", function()
        if draggedSpell then local value = draggedSpell draggedSpell = nil addEntry(value) end
    end)
    win.dropZone:SetScript("OnMouseUp", function()
        if draggedSpell then local value = draggedSpell draggedSpell = nil addEntry(value) end
    end)
    win.emptyEntries = text(win.dropZone, "GameFontHighlightSmall", "Empty bar. Drag a spell here,\nor add a name/ID below.", DIM)
    win.emptyEntries:SetPoint("CENTER", 0, -5)
    win.emptyEntries:SetJustifyH("CENTER")
    win.noSelection = text(win.dropZone, "GameFontHighlightSmall", "Create or select a bar.", DIM)
    win.noSelection:SetPoint("CENTER", 0, -5)

    win.entryTitle = text(detail, "GameFontHighlightSmall", "Select an entry")
    win.entryTitle:SetPoint("TOPLEFT", 276, -54)
    win.entryTitle:SetWidth(166)
    win.entryTitle:SetJustifyH("LEFT")
    win.entryTitle:SetWordWrap(false)
    win.modeButton = flatButton(detail, "Mode: -", 166, 22, function()
        local bar = currentBar()
        local entry = bar and selectedEntry and bar.entries[selectedEntry]
        if entry then setEntryOption("mode", nextMode(entry)) end
    end)
    win.modeButton:SetPoint("TOPLEFT", 276, -78)
    win.readyButton = flatButton(detail, "Ready: -", 166, 22, function()
        local bar = currentBar()
        local entry = bar and selectedEntry and bar.entries[selectedEntry]
        if entry then setEntryOption("readyVisibility", cycle(entry.readyVisibility, { "always", "combat", "hide" })) end
    end)
    win.readyButton:SetPoint("TOPLEFT", 276, -106)
    win.inactiveButton = flatButton(detail, "Inactive: -", 166, 22, function()
        local bar = currentBar()
        local entry = bar and selectedEntry and bar.entries[selectedEntry]
        if entry then setEntryOption("inactiveVisibility", entry.inactiveVisibility == "hide" and "show" or "hide") end
    end)
    win.inactiveButton:SetPoint("TOPLEFT", 276, -134)
    local durationLabel = text(detail, "GameFontHighlightSmall", "Duration: auto or seconds", DIM)
    durationLabel:SetPoint("TOPLEFT", 276, -165)
    win.durationBox = editBox(detail, "ForeverCDMAdvancedDuration", 108, 22)
    win.durationBox:SetPoint("TOPLEFT", 276, -183)
    local function applyDuration()
        local value = win.durationBox:GetText()
        if value == "" or string.lower(value) == "auto" then value = nil else value = tonumber(value) end
        if value == nil and string.lower(win.durationBox:GetText()) ~= "auto" and win.durationBox:GetText() ~= "" then
            rejected(nil, "Duration must be auto or a number of seconds.")
            return
        end
        setEntryOption("duration", value)
        win.durationBox:ClearFocus()
    end
    win.durationBox:SetScript("OnEnterPressed", applyDuration)
    win.durationApply = flatButton(detail, "Set", 52, 22, applyDuration)
    win.durationApply:SetPoint("LEFT", win.durationBox, "RIGHT", 6, 0)
    win.combine = checkbox(detail, "Combine with previous", function(self)
        local bar = currentBar()
        if bar and selectedEntry and selectedEntry > 1 then
            local ok, reason = CDM.SetEntryCombined(bar.id, selectedEntry, self:GetChecked() and true or false)
            if ok == false then rejected(reason, "Could not combine this entry.") else changed() end
        end
    end)
    win.combine:SetPoint("TOPLEFT", 276, -215)

    win.upButton = flatButton(detail, "Up", 62, 22, function()
        local bar = currentBar()
        if bar and selectedEntry and selectedEntry > 1 then
            local ok, reason = CDM.MoveEntry(bar.id, selectedEntry, -1)
            if ok then selectedEntry = selectedEntry - 1 changed()
            else rejected(reason, "Could not move this entry.") end
        end
    end)
    win.upButton:SetPoint("TOPLEFT", 8, -270)
    win.downButton = flatButton(detail, "Down", 62, 22, function()
        local bar = currentBar()
        if bar and selectedEntry and selectedEntry < #bar.entries then
            local ok, reason = CDM.MoveEntry(bar.id, selectedEntry, 1)
            if ok then selectedEntry = selectedEntry + 1 changed()
            else rejected(reason, "Could not move this entry.") end
        end
    end)
    win.downButton:SetPoint("LEFT", win.upButton, "RIGHT", 5, 0)
    win.removeButton = flatButton(detail, "Remove", 78, 22, function()
        local bar = currentBar()
        if bar and selectedEntry then
            CDM.RemoveEntry(bar.id, selectedEntry)
            if selectedEntry > #(CDM.GetBar(bar.id).entries or {}) then selectedEntry = selectedEntry - 1 end
            if selectedEntry == 0 then selectedEntry = nil end
            changed()
        end
    end)
    win.removeButton:SetPoint("LEFT", win.downButton, "RIGHT", 5, 0)
    win.addBox = editBox(detail, "ForeverCDMAdvancedConfigAdd", 166, 22)
    win.addBox:SetPoint("TOPLEFT", 276, -270)
    win.addBox:SetScript("OnEnterPressed", function(self) addEntry(self:GetText()) end)
    local addButton = flatButton(detail, "Add name / ID / item link", 166, 22, function() addEntry(win.addBox:GetText()) end)
    addButton:SetPoint("TOPLEFT", 276, -297)

    local divider = detail:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -328)
    divider:SetPoint("TOPRIGHT", -8, -328)

    local function stepper(label, x, y, key, amount)
        local caption = text(detail, "GameFontHighlightSmall", label, DIM)
        caption:SetPoint("TOPLEFT", x, y)
        local minus = flatButton(detail, "-", 22, 22, function()
            local bar = currentBar()
            if bar then setBarOption(key, (bar[key] or 0) - amount) end
        end)
        minus:SetPoint("TOPLEFT", x, y - 20)
        local value = text(detail, "GameFontHighlight", "-")
        value:SetPoint("LEFT", minus, "RIGHT", 12, 0)
        local plus = flatButton(detail, "+", 22, 22, function()
            local bar = currentBar()
            if bar then setBarOption(key, (bar[key] or 0) + amount) end
        end)
        plus:SetPoint("TOPLEFT", x + 76, y - 20)
        return value
    end
    win.sizeValue = stepper("Icon size", 10, -342, "size", 2)
    win.spacingValue = stepper("Spacing", 120, -342, "spacing", 1)
    win.rowsValue = stepper("Rows", 230, -342, "rows", 1)
    win.columnsValue = stepper("Columns", 340, -342, "columns", 1)
    win.growX = flatButton(detail, "Horizontal: RIGHT", 142, 22, function()
        local bar = currentBar()
        if bar then setBarOption("growX", bar.growX == "RIGHT" and "LEFT" or "RIGHT") end
    end)
    win.growX:SetPoint("TOPLEFT", 10, -397)
    win.growY = flatButton(detail, "Vertical: DOWN", 142, 22, function()
        local bar = currentBar()
        if bar then setBarOption("growY", bar.growY == "DOWN" and "UP" or "DOWN") end
    end)
    win.growY:SetPoint("TOPLEFT", 158, -397)
    win.procMode = flatButton(detail, "Proc cooldown: red", 142, 22, function()
        local bar = currentBar()
        if bar then setBarOption("procCooldownMode", bar.procCooldownMode == "red" and "hide" or "red") end
    end)
    win.procMode:SetPoint("TOPLEFT", 306, -397)
    win.autoButton = flatButton(detail, "Auto-fill selected", 142, 22, function()
        local bar = currentBar()
        if not bar then return end
        local count = CDM.Auto(bar.id)
        changed()
        notice("Added " .. tostring(count or 0) .. " entries to " .. tostring(bar.name) .. ".")
    end)
    win.autoButton:SetPoint("TOPLEFT", 10, -425)
    win.clearButton = flatButton(detail, "Clear selected", 142, 22, function()
        local bar = currentBar()
        if bar then CDM.ClearBar(bar.id) selectedEntry = nil changed() end
    end)
    win.clearButton:SetPoint("TOPLEFT", 158, -425)

    win.lockButton = flatButton(detail, "Lock bars", 142, 22, function()
        CDM.SetLocked(not settings().locked)
        CDM.Persist()
        refreshUI()
    end)
    win.lockButton:SetPoint("TOPLEFT", 306, -425)
    win.names = checkbox(detail, "Show spell names", function(self)
        settings().showNames = self:GetChecked() and true or false
        changed()
    end)
    win.names:SetPoint("TOPLEFT", 10, -461)
    win.minimap = checkbox(detail, "Minimap button", function(self)
        ForeverCDMAdvanced_SetMinimapShown(self:GetChecked() and true or false)
    end)
    win.minimap:SetPoint("TOPLEFT", 142, -461)
    win.fadeButton = flatButton(detail, "Out of combat: show", 166, 22, function()
        local s = settings()
        s.fade = s.fade == nil and "fade" or s.fade == "fade" and "hide" or nil
        changed()
    end)
    win.fadeButton:SetPoint("TOPLEFT", 276, -456)

    win.appearanceOverlay = CreateFrame("Frame", nil, win)
    win.appearanceOverlay:SetAllPoints(win)
    win.appearanceOverlay:SetFrameLevel(win:GetFrameLevel() + 20)
    win.appearanceOverlay:EnableMouse(true)
    fill(win.appearanceOverlay, "BACKGROUND", { 0, 0, 0 }, 0.72)

    win.appearancePanel = CreateFrame("Frame", nil, win.appearanceOverlay)
    win.appearancePanel:SetSize(570, 500)
    win.appearancePanel:SetPoint("CENTER")
    win.appearancePanel:SetFrameLevel(win.appearanceOverlay:GetFrameLevel() + 1)
    fill(win.appearancePanel, "BACKGROUND", BG, 0.995)
    outline(win.appearancePanel, LINE)

    local appearance = {}
    win.appearance = appearance
    appearance.title = text(win.appearancePanel, "GameFontNormal", "APPEARANCE", ACCENT)
    appearance.title:SetPoint("TOPLEFT", 16, -16)
    appearance.title:SetPoint("RIGHT", -90, 0)
    appearance.title:SetJustifyH("LEFT")
    appearance.title:SetWordWrap(false)
    local appearanceClose = flatButton(win.appearancePanel, "Close", 64, 24, function() win.appearanceOverlay:Hide() end)
    appearanceClose:SetPoint("TOPRIGHT", -12, -10)

    local borderHeading = text(win.appearancePanel, "GameFontNormalSmall", "BORDER", ACCENT)
    borderHeading:SetPoint("TOPLEFT", 18, -54)
    appearance.borderMode = flatButton(win.appearancePanel, "Border mode: None", 250, 24, function()
        local bar = currentBar()
        if bar then setBarOption("borderMode", cycle(bar.borderMode, { "none", "solid", "eui" })) end
    end)
    appearance.borderMode:SetPoint("TOPLEFT", 18, -76)
    appearance.borderSource = flatButton(win.appearancePanel, "EUI source: MainBar", 250, 24, function()
        local bar = currentBar()
        if bar then
            setBarOption("borderSource", cycle(bar.borderSource, {
                "MainBar", "Bar2", "Bar3", "Bar4", "Bar5", "Bar6", "Bar7", "Bar8", "Bar9", "Bar10",
            }))
        end
    end)
    appearance.borderSource:SetPoint("TOPLEFT", 302, -76)
    appearance.euiHint = text(win.appearancePanel, "GameFontDisableSmall",
        "Full appearance sync uses the selected EUI source. Focus and mouseover behavior are not synced.", DIM)
    appearance.euiHint:SetPoint("TOPLEFT", 18, -108)
    appearance.euiHint:SetWidth(534)
    appearance.euiHint:SetJustifyH("LEFT")
    appearance.euiHint:SetWordWrap(true)

    local function appearanceStepper(label, x, y, key, minimum, maximum)
        local stepper = {}
        stepper.caption = text(win.appearancePanel, "GameFontHighlightSmall", label, DIM)
        stepper.caption:SetPoint("TOPLEFT", x, y)
        stepper.minus = flatButton(win.appearancePanel, "-", 24, 24, function()
            local bar = currentBar()
            if bar then setBarOption(key, math.max(minimum, math.min(maximum, (tonumber(bar[key]) or minimum) - 1))) end
        end)
        stepper.minus:SetPoint("TOPLEFT", x, y - 22)
        stepper.value = text(win.appearancePanel, "GameFontHighlight", "-")
        stepper.value:SetPoint("LEFT", stepper.minus, "RIGHT", 14, 0)
        stepper.plus = flatButton(win.appearancePanel, "+", 24, 24, function()
            local bar = currentBar()
            if bar then setBarOption(key, math.max(minimum, math.min(maximum, (tonumber(bar[key]) or minimum) + 1))) end
        end)
        stepper.plus:SetPoint("TOPLEFT", x + 82, y - 22)
        return stepper
    end

    local function colorSwatch(label, x, y, key, defaults)
        local swatch = CreateFrame("Button", nil, win.appearancePanel)
        swatch:SetSize(106, 24)
        swatch:SetPoint("TOPLEFT", x, y - 22)
        swatch.bg = fill(swatch, "BACKGROUND", BTN)
        outline(swatch, LINE)
        swatch.color = swatch:CreateTexture(nil, "ARTWORK")
        swatch.color:SetPoint("TOPLEFT", 5, -5)
        swatch.color:SetPoint("BOTTOMRIGHT", -5, 5)
        swatch.caption = text(win.appearancePanel, "GameFontHighlightSmall", label, DIM)
        swatch.caption:SetPoint("TOPLEFT", x, y)
        swatch:SetScript("OnClick", function() openBarColorPicker(key, defaults) end)
        swatch:SetScript("OnEnter", function(self) self.bg:SetColorTexture(BTN_HI[1], BTN_HI[2], BTN_HI[3], 1) end)
        swatch:SetScript("OnLeave", function(self) self.bg:SetColorTexture(BTN[1], BTN[2], BTN[3], 1) end)
        return swatch
    end

    appearance.borderSize = appearanceStepper("Solid / fallback size", 18, -146, "borderSize", 0, 8)
    appearance.borderColor = colorSwatch("Solid / fallback color", 160, -146, "borderColor", { 0, 0, 0, 1 })

    local glowDivider = win.appearancePanel:CreateTexture(nil, "ARTWORK")
    glowDivider:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    glowDivider:SetHeight(1)
    glowDivider:SetPoint("TOPLEFT", 18, -210)
    glowDivider:SetPoint("TOPRIGHT", -18, -210)
    local glowHeading = text(win.appearancePanel, "GameFontNormalSmall", "PROC GLOW", ACCENT)
    glowHeading:SetPoint("TOPLEFT", 18, -228)
    appearance.procGlow = checkbox(win.appearancePanel, "Enable proc glow", function(self)
        setBarOption("procGlowEnabled", self:GetChecked() and true or false)
    end)
    appearance.procGlow:SetPoint("TOPLEFT", 18, -253)
    appearance.glowSize = appearanceStepper("Glow size", 18, -286, "procGlowSize", 0, 20)
    appearance.glowColor = colorSwatch("Glow color", 160, -286, "procGlowColor", { 1, 0.82, 0.1, 1 })

    local fontDivider = win.appearancePanel:CreateTexture(nil, "ARTWORK")
    fontDivider:SetColorTexture(LINE[1], LINE[2], LINE[3], 1)
    fontDivider:SetHeight(1)
    fontDivider:SetPoint("TOPLEFT", 18, -350)
    fontDivider:SetPoint("TOPRIGHT", -18, -350)
    local fontHeading = text(win.appearancePanel, "GameFontNormalSmall", "FONT", ACCENT)
    fontHeading:SetPoint("TOPLEFT", 18, -368)
    appearance.fontFace = flatButton(win.appearancePanel, "Font face: -", 250, 24, function()
        local bar = currentBar()
        if bar then setBarOption("fontFace", cycle(bar.fontFace, { "ellesmere", "friz", "arial", "skurri", "morpheus" })) end
    end)
    appearance.fontFace:SetPoint("TOPLEFT", 18, -392)
    appearance.fontOutline = flatButton(win.appearancePanel, "Outline: -", 250, 24, function()
        local bar = currentBar()
        if bar then setBarOption("fontOutline", cycle(bar.fontOutline, { "NONE", "OUTLINE", "THICKOUTLINE" })) end
    end)
    appearance.fontOutline:SetPoint("TOPLEFT", 302, -392)
    appearance.fontSize = appearanceStepper("Font size", 18, -430, "fontSize", 6, 64)
    win.appearanceOverlay:Hide()

    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ForeverCDMAdvanced", "Version")
    local footer = text(win, "GameFontDisableSmall", "v" .. tostring(version or "?") .. "   /fcdma help for commands")
    footer:SetPoint("BOTTOMLEFT", 16, 12)
    local footerHint = text(win, "GameFontDisableSmall", "Items stay in cooldown mode; rejected changes are reported in chat.")
    footerHint:SetPoint("BOTTOMRIGHT", -16, 12)

    win:SetScript("OnShow", function(self)
        local width = UIParent:GetWidth() or 980
        local height = UIParent:GetHeight() or 620
        self:SetScale(math.min(1, (width - 20) / 980, (height - 20) / 620))
        refreshUI()
    end)
    win:Hide()
end

function ForeverCDMAdvanced_ToggleConfig()
    if not win then build() end
    if win:IsShown() then win:Hide() else win:Show() end
end

function ForeverCDMAdvanced_RefreshConfig()
    if win and win:IsShown() then refreshUI() end
end

-- Minimap button ------------------------------------------------------------------

local minimapButton
local atan2 = math.atan2 or math.atan

local function placeMinimap()
    local minimap = settings().minimap
    local angle = math.rad(minimap.angle or 215)
    local half = (Minimap:GetWidth() or 140) / 2
    local x, y = math.cos(angle) * (half + 6), math.sin(angle) * (half + 6)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        x = math.max(-half, math.min(half, x * 1.42))
        y = math.max(-half, math.min(half, y * 1.42))
    end
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function buildMinimap()
    minimapButton = CreateFrame("Button", "ForeverCDMAdvancedMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = minimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON_PATH)
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    local ring = minimapButton:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    minimapButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            CDM.SetLocked(not settings().locked)
            CDM.Persist()
            ForeverCDMAdvanced_RefreshConfig()
            notice("Bars " .. (settings().locked and "locked." or "unlocked; drag them into place."))
        else
            ForeverCDMAdvanced_ToggleConfig()
        end
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local centerX, centerY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            settings().minimap.angle = math.deg(atan2(cursorY / scale - centerY, cursorX / scale - centerX))
            placeMinimap()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        CDM.Persist()
    end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cffd2621fForever|r Cooldown Manager")
        GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right-click: lock or unlock bars", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.64)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ForeverCDMAdvanced_SetMinimapShown(shown)
    settings().minimap.hide = not shown
    CDM.Refresh()
    CDM.Persist()
    if not Minimap then return end
    if shown and not minimapButton then buildMinimap() end
    if minimapButton then
        minimapButton:SetShown(shown)
        if shown then placeMinimap() end
    end
    if win and win:IsShown() then win.minimap:SetChecked(shown) end
end

function ForeverCDMAdvanced_InitMinimap()
    ForeverCDMAdvanced_SetMinimapShown(not settings().minimap.hide)
end
