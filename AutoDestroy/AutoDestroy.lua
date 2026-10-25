-- AutoDestroy: milling, prospecting, disenchanting with one click/keypress per stack/item (WotLK 3.3.5a)
-- Blizzard only allows spell casts from a hardware event, so: 1 click or keypress = 1 cast.

local BIND_ACTION = "CLICK AutoDestroyButton:Key"
BINDING_HEADER_AUTODESTROY = "AutoDestroy"
_G["BINDING_NAME_" .. BIND_ACTION] = "Mill / prospect / disenchant next item"

local defaults = {
    mill       = true,
    prospect   = true,
    disenchant = true,
    maxQuality = 3,     -- 2 = green, 3 = blue, 4 = epic
    soulbound  = false, -- include soulbound items
    autoloot   = true,
    autoaccept = true,  -- auto-confirm the enchant popups (replace enchant / becomes soulbound)
    shown      = true,
    ignore     = {},
}

local SPELL_MILL, SPELL_PROSPECT, SPELL_DE = 51005, 31252, 13262
local SPELL_OF = { mill = SPELL_MILL, prospect = SPELL_PROSPECT, disenchant = SPELL_DE }
local LABEL = { mill = "Milling", prospect = "Prospecting", disenchant = "Disenchant" }
local KINDS = { "mill", "prospect", "disenchant" }
local QNAME = { [2] = "|cff1eff00green|r", [3] = "|cff0070ddblue|r", [4] = "|cffa335eeepic|r" }

local db
local current            -- next item: { kind, bag, slot, link, texture, id, count }
local candidates = {}    -- processable items (not removed), one entry per item ID
local allItems = {}      -- same, but including removed items (for the list window)
local preferredId        -- item picked by the user
local remaining = 0
local lootUntil = 0
local dirty = true
local hidePopups = false
local active = false     -- true only if the character knows Milling, Prospecting or Disenchant
local listFrame, optionsPanel
local RefreshList

local CLASS_WEAPON, CLASS_ARMOR = GetAuctionItemClasses()

local tip = CreateFrame("GameTooltip", "AutoDestroyTip", nil, "GameTooltipTemplate")
tip:SetOwner(UIParent, "ANCHOR_NONE")

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffc040AutoDestroy:|r " .. msg)
end

local function OnOff(v) return v and "|cff40ff40on|r" or "|cffff4040off|r" end

local function SpellName(id)
    local name = GetSpellInfo(id)
    -- GetSpellInfo(name) only returns something if the spell is in the spellbook
    if name and GetSpellInfo(name) then return name end
end

-- reads a bag slot tooltip: millable, prospectable, soulbound
local function ScanTooltip(bag, slot)
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    tip:SetBagItem(bag, slot)
    local millable, prospectable, bound
    for i = 1, tip:NumLines() do
        local fs = _G["AutoDestroyTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text == ITEM_MILLABLE then millable = true
        elseif text == ITEM_PROSPECTABLE then prospectable = true
        elseif text == ITEM_SOULBOUND then bound = true end
    end
    return millable, prospectable, bound
end

local function Scan()
    local spellMill = db.mill and SpellName(SPELL_MILL)
    local spellProspect = db.prospect and SpellName(SPELL_PROSPECT)
    local spellDE = db.disenchant and SpellName(SPELL_DE)

    local lists = { mill = {}, prospect = {}, disenchant = {} }
    local byId = {}
    local count = 0

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local texture, stack, locked = GetContainerItemInfo(bag, slot)
            local link = texture and GetContainerItemLink(bag, slot)
            local id = link and tonumber(string.match(link, "item:(%d+)"))
            if id and not locked then
                stack = stack or 1
                local _, _, quality, _, _, itemType, _, _, equipLoc = GetItemInfo(link)
                local kind
                if (spellMill or spellProspect) and stack >= 5 then
                    local millable, prospectable = ScanTooltip(bag, slot)
                    if millable and spellMill then kind = "mill"
                    elseif prospectable and spellProspect then kind = "prospect" end
                end
                if not kind and spellDE and quality and quality >= 2 and quality <= db.maxQuality
                    and equipLoc and equipLoc ~= ""
                    and (itemType == CLASS_WEAPON or itemType == CLASS_ARMOR) then
                    local _, _, bound = ScanTooltip(bag, slot)
                    if db.soulbound or not bound then kind = "disenchant" end
                end
                if kind then
                    local e = byId[id]
                    if not e then
                        e = { kind = kind, bag = bag, slot = slot, link = link, texture = texture,
                              id = id, count = 0, ignored = db.ignore[id] and true or false }
                        byId[id] = e
                        table.insert(lists[kind], e)
                    end
                    e.count = e.count + stack
                    if not e.ignored then count = count + 1 end
                end
            end
        end
    end

    remaining = count
    candidates, allItems = {}, {}
    for _, kind in ipairs(KINDS) do
        for _, e in ipairs(lists[kind]) do
            table.insert(allItems, e)
            if not e.ignored then table.insert(candidates, e) end
        end
    end
    current = candidates[1]
    for _, c in ipairs(candidates) do
        if c.id == preferredId then current = c break end
    end
end

---------------------------------------------------------------------------
-- Main button
---------------------------------------------------------------------------
local btn = CreateFrame("Button", "AutoDestroyButton", UIParent, "SecureActionButtonTemplate")
btn:SetWidth(40); btn:SetHeight(40)
btn:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
btn:SetMovable(true)
btn:SetClampedToScreen(true)
btn:RegisterForClicks("AnyUp")
btn:RegisterForDrag("LeftButton")
btn:SetAttribute("type", "macro")
btn:SetAttribute("macrotext", "")

btn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
})
btn:SetBackdropColor(0, 0, 0, 0.7)
btn:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", 2, -2)
icon:SetPoint("BOTTOMRIGHT", -2, 2)
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local countText = btn:CreateFontString(nil, "OVERLAY")
countText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
countText:SetPoint("BOTTOMRIGHT", -2, 3)

local kindText = btn:CreateFontString(nil, "OVERLAY")
kindText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
kindText:SetPoint("TOP", btn, "BOTTOM", 0, -2)

btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

local function UpdateDisplay()
    if current then
        icon:SetTexture(current.texture)
        icon:SetDesaturated(false)
        countText:SetText(remaining)
        kindText:SetText(LABEL[current.kind])
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetDesaturated(true)
        countText:SetText("")
        kindText:SetText("nothing")
    end
end

local function Refresh()
    if not db then return end
    active = (SpellName(SPELL_MILL) or SpellName(SPELL_PROSPECT) or SpellName(SPELL_DE)) and true or false
    if not InCombatLockdown() then
        if active and db.shown then btn:Show() else btn:Hide() end
    end
    if not active then
        -- character has none of the three professions: stay dormant
        current, candidates, allItems, remaining = nil, {}, {}, 0
        if listFrame then listFrame:Hide() end
        return
    end
    Scan()
    UpdateDisplay()
    if GameTooltip:IsOwned(btn) then btn:GetScript("OnEnter")(btn) end
    if listFrame and listFrame:IsShown() then RefreshList() end
end

local function ToggleList()
    if listFrame:IsShown() then
        listFrame:Hide()
    else
        listFrame:Show()
        RefreshList()
    end
end

btn:SetScript("PreClick", function(self, button)
    if InCombatLockdown() then return end
    if not active then self:SetAttribute("macrotext", "") return end
    Scan()
    -- "Key" is the virtual button used by the keybind: it always does the action
    if button == "LeftButton" and IsShiftKeyDown() then
        UpdateDisplay()
        self:SetAttribute("macrotext", "")
        ToggleList()
        return
    end
    if button == "RightButton" then
        -- switch to the next item, cast nothing
        local n = #candidates
        if n > 0 then
            local idx = 1
            for i, c in ipairs(candidates) do
                if c == current then idx = i break end
            end
            current = candidates[idx % n + 1]
            preferredId = current.id
        end
        UpdateDisplay()
        if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
        if listFrame:IsShown() then RefreshList() end
        self:SetAttribute("macrotext", "")
        return
    end
    UpdateDisplay()
    local text = ""
    if current and not UnitCastingInfo("player") and not LootFrame:IsShown() then
        local spell = SpellName(SPELL_OF[current.kind])
        if spell then
            text = "/cast " .. spell .. "\n/use " .. current.bag .. " " .. current.slot
            lootUntil = GetTime() + 8
        end
    end
    self:SetAttribute("macrotext", text)
end)

btn:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
end)
btn:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("AutoDestroy")
    if current then
        GameTooltip:AddDoubleLine(LABEL[current.kind] .. ":", current.link, 1, 1, 1)
        GameTooltip:AddLine(remaining .. " stacks/items left", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine("Nothing to process in your bags.", 0.7, 0.7, 0.7)
    end
    local key = GetBindingKey(BIND_ACTION)
    GameTooltip:AddLine("Left-click" .. (key and (" or " .. key) or "") .. ": process the shown item", 0.5, 0.8, 1)
    GameTooltip:AddLine("Right-click: pick another item", 0.5, 0.8, 1)
    GameTooltip:AddLine("Shift+click: item list", 0.5, 0.8, 1)
    GameTooltip:AddLine("Shift+drag: move the button", 0.5, 0.8, 1)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Keybind buttons (shared by the list window and the options panel)
---------------------------------------------------------------------------
local keyButtons = {}
local MODS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, UNKNOWN = 1 }

local function UpdateKeyButtons()
    for _, b in ipairs(keyButtons) do
        if not b.capturing then b:SetText(GetBindingKey(BIND_ACTION) or "Not bound") end
    end
end

local function SetKey(key)
    if InCombatLockdown() then Print("Not possible in combat.") return end
    local k1, k2 = GetBindingKey(BIND_ACTION)
    if k1 then SetBinding(k1) end
    if k2 then SetBinding(k2) end
    if key then SetBinding(key, BIND_ACTION) end
    SaveBindings(GetCurrentBindingSet())
end

local function StopCapture(b)
    b.capturing = nil
    b:EnableKeyboard(false)
    b:SetScript("OnKeyDown", nil)
    UpdateKeyButtons()
end

-- left-click: press a key to bind (Esc cancels), right-click: unbind
local function MakeKeyButton(parent, name, width)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetWidth(width); b:SetHeight(22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            SetKey(nil)
            StopCapture(self)
            return
        end
        self.capturing = true
        self:SetText("Press a key...")
        self:EnableKeyboard(true)
        self:SetScript("OnKeyDown", function(_, key)
            if MODS[key] then return end
            if key ~= "ESCAPE" then
                if IsShiftKeyDown() then key = "SHIFT-" .. key end
                if IsControlKeyDown() then key = "CTRL-" .. key end
                if IsAltKeyDown() then key = "ALT-" .. key end
                SetKey(key)
            end
            StopCapture(self)
        end)
    end)
    b:SetScript("OnHide", function(self) StopCapture(self) end)
    table.insert(keyButtons, b)
    return b
end

---------------------------------------------------------------------------
-- Item list window
---------------------------------------------------------------------------
local ROWS, ROW_H = 14, 20
local rows = {}
local display = {}
local offset = 0

listFrame = CreateFrame("Frame", "AutoDestroyList", UIParent)
listFrame:SetWidth(300); listFrame:SetHeight(ROWS * ROW_H + 112)
listFrame:SetPoint("CENTER", UIParent, "CENTER", 220, 0)
listFrame:SetFrameStrata("DIALOG")
listFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
})
listFrame:SetBackdropColor(0, 0, 0, 0.85)
listFrame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
listFrame:SetMovable(true)
listFrame:SetClampedToScreen(true)
listFrame:EnableMouse(true)
listFrame:EnableMouseWheel(true)
listFrame:RegisterForDrag("LeftButton")
listFrame:SetScript("OnDragStart", listFrame.StartMoving)
listFrame:SetScript("OnDragStop", listFrame.StopMovingOrSizing)
listFrame:Hide()
tinsert(UISpecialFrames, "AutoDestroyList")

local title = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 10, -9)
title:SetText("AutoDestroy - items")

local close = CreateFrame("Button", nil, listFrame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)

local hint = listFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("BOTTOMLEFT", 10, 58)
hint:SetWidth(280); hint:SetJustifyH("LEFT")
hint:SetText("Shift+click: remove / add back    Click: pick as next")

local boundCheck = CreateFrame("CheckButton", "AutoDestroyListSoulbound", listFrame, "UICheckButtonTemplate")
boundCheck:SetWidth(24); boundCheck:SetHeight(24)
boundCheck:SetPoint("BOTTOMLEFT", 6, 30)
AutoDestroyListSoulboundText:SetText("Show soulbound items")
boundCheck:SetScript("OnClick", function(self)
    db.soulbound = self:GetChecked() and true or false
    Refresh()
end)

local listKeyLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
listKeyLabel:SetPoint("BOTTOMLEFT", 10, 12)
listKeyLabel:SetText("Keybind:")

local listKeyBtn = MakeKeyButton(listFrame, "AutoDestroyListKey", 130)
listKeyBtn:SetPoint("LEFT", listKeyLabel, "RIGHT", 6, 0)
listKeyBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Keybind for the action")
    GameTooltip:AddLine("Left-click, then press a key (Esc cancels).", 1, 1, 1)
    GameTooltip:AddLine("Right-click: unbind.", 1, 1, 1)
    GameTooltip:Show()
end)
listKeyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local listCredit = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
listCredit:SetPoint("BOTTOMRIGHT", -10, 12)
listCredit:SetText("|cffffd100made by feralpaw|r")

for i = 1, ROWS do
    local row = CreateFrame("Button", nil, listFrame)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 8, -30 - (i - 1) * ROW_H)
    row:SetPoint("RIGHT", listFrame, "RIGHT", -8, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(ROW_H - 2); row.icon:SetHeight(ROW_H - 2)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", -2, 0)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    row.text:SetJustifyH("LEFT")

    row:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if IsShiftKeyDown() then
            if db.ignore[e.id] then
                db.ignore[e.id] = nil
            else
                db.ignore[e.id] = true
                if preferredId == e.id then preferredId = nil end
            end
        elseif not e.ignored then
            preferredId = e.id
        end
        Refresh()
    end)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.entry.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
end

RefreshList = function()
    boundCheck:SetChecked(db.soulbound)
    UpdateKeyButtons()

    display = {}
    for _, kind in ipairs(KINDS) do
        local header = false
        for _, e in ipairs(allItems) do
            if e.kind == kind then
                if not header then
                    table.insert(display, { header = LABEL[kind] })
                    header = true
                end
                table.insert(display, e)
            end
        end
    end
    if #display == 0 then
        table.insert(display, { header = "Nothing to process in your bags." })
    end

    local maxOffset = math.max(0, #display - ROWS)
    if offset > maxOffset then offset = maxOffset end

    for i = 1, ROWS do
        local row = rows[i]
        local d = display[i + offset]
        if not d then
            row:Hide()
        elseif d.header then
            row.entry = nil
            row.icon:Hide()
            row.count:SetText("")
            row.text:SetText("|cffffc040" .. d.header .. "|r")
            row:EnableMouse(false)
            row:Show()
        else
            row.entry = d
            row.icon:SetTexture(d.texture)
            row.icon:SetDesaturated(d.ignored)
            row.icon:Show()
            row.count:SetText(d.count)
            if d.ignored then
                local name = GetItemInfo(d.link) or "?"
                row.text:SetText("|cff808080" .. name .. " (removed)|r")
            elseif current and d.id == current.id then
                row.text:SetText("|cffffffff>|r " .. d.link)
            else
                row.text:SetText(d.link)
            end
            row:EnableMouse(true)
            row:Show()
        end
    end
end

listFrame:SetScript("OnMouseWheel", function(self, delta)
    local maxOffset = math.max(0, #display - ROWS)
    offset = math.max(0, math.min(maxOffset, offset - delta))
    RefreshList()
end)

---------------------------------------------------------------------------
-- Options panel (Esc > Interface > AddOns > AutoDestroy)
---------------------------------------------------------------------------
optionsPanel = CreateFrame("Frame", "AutoDestroyOptions", UIParent)
optionsPanel.name = "AutoDestroy"

do
    local p = optionsPanel
    local head = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 16, -16)
    head:SetText("AutoDestroy")

    local checks = {}
    local function Check(key, label, y, needsOutOfCombat)
        local cb = CreateFrame("CheckButton", "AutoDestroyOpt_" .. key, p, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, y)
        _G["AutoDestroyOpt_" .. key .. "Text"]:SetText(label)
        cb:SetScript("OnClick", function(self)
            if needsOutOfCombat and InCombatLockdown() then
                self:SetChecked(db[key])
                Print("Not possible in combat.")
                return
            end
            db[key] = self:GetChecked() and true or false
            Refresh()
        end)
        checks[key] = cb
    end

    Check("mill", "Milling", -50)
    Check("prospect", "Prospecting", -76)
    Check("disenchant", "Disenchanting", -102)
    Check("soulbound", "Include soulbound items (careful: this can be your own gear)", -128)
    Check("autoloot", "Auto loot the results", -154)
    Check("shown", "Show the button", -180, true)
    Check("autoaccept", "Auto-accept enchant confirmations (replace enchant / becomes soulbound)", -206)

    local qBtn = CreateFrame("Button", "AutoDestroyOptQuality", p, "UIPanelButtonTemplate")
    qBtn:SetWidth(220); qBtn:SetHeight(22)
    qBtn:SetPoint("TOPLEFT", 20, -242)
    qBtn:SetScript("OnClick", function()
        db.maxQuality = db.maxQuality >= 4 and 2 or db.maxQuality + 1
        qBtn:SetText("Disenchant up to: " .. QNAME[db.maxQuality])
        Refresh()
    end)

    -- keybind
    local keyLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    keyLabel:SetPoint("TOPLEFT", 20, -284)
    keyLabel:SetText("Keybind for the action:")

    local keyBtn = MakeKeyButton(p, "AutoDestroyOptKey", 160)
    keyBtn:SetPoint("TOPLEFT", 20, -302)

    local clearBtn = CreateFrame("Button", "AutoDestroyOptKeyClear", p, "UIPanelButtonTemplate")
    clearBtn:SetWidth(80); clearBtn:SetHeight(22)
    clearBtn:SetPoint("LEFT", keyBtn, "RIGHT", 6, 0)
    clearBtn:SetText("Unbind")
    clearBtn:SetScript("OnClick", function()
        SetKey(nil)
        StopCapture(keyBtn)
    end)

    local keyHint = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    keyHint:SetPoint("TOPLEFT", 20, -330)
    keyHint:SetText("Click the button, then press a key (Esc cancels). Also under Esc > Key Bindings > AutoDestroy.")

    local listBtn = CreateFrame("Button", "AutoDestroyOptList", p, "UIPanelButtonTemplate")
    listBtn:SetWidth(160); listBtn:SetHeight(22)
    listBtn:SetPoint("TOPLEFT", 20, -362)
    listBtn:SetText("Open item list")
    listBtn:SetScript("OnClick", function() if active then Scan() ToggleList() end end)

    local credit = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    credit:SetPoint("BOTTOMLEFT", 16, 16)
    credit:SetText("|cffffd100made by feralpaw|r")

    p:SetScript("OnShow", function()
        if not db then return end
        for key, cb in pairs(checks) do cb:SetChecked(db[key]) end
        qBtn:SetText("Disenchant up to: " .. QNAME[db.maxQuality])
        UpdateKeyButtons()
    end)
end

InterfaceOptions_AddCategory(optionsPanel)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("BAG_UPDATE")
f:RegisterEvent("LOOT_OPENED")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("REPLACE_ENCHANT")
f:RegisterEvent("BIND_ENCHANT")

f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        AutoDestroyDB = AutoDestroyDB or {}
        db = AutoDestroyDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        if type(db.ignore) ~= "table" then db.ignore = {} end
        btn:Hide()
        dirty = true
    elseif event == "REPLACE_ENCHANT" or event == "BIND_ENCHANT" then
        -- confirm the "replace existing enchant" / "item becomes soulbound" popups
        if db and db.autoaccept then
            if event == "REPLACE_ENCHANT" then ReplaceEnchant() else BindEnchant() end
            StaticPopup_Hide(event)
            hidePopups = true
        end
    elseif event == "LOOT_OPENED" then
        if db and db.autoloot and GetTime() < lootUntil then
            for i = GetNumLootItems(), 1, -1 do LootSlot(i) end
        end
    else
        dirty = true
    end
end)

-- bag scans are batched instead of running on every single BAG_UPDATE
local elapsed = 0
f:SetScript("OnUpdate", function(self, e)
    elapsed = elapsed + e
    if elapsed < 0.3 then return end
    elapsed = 0
    if hidePopups then
        hidePopups = false
        StaticPopup_Hide("REPLACE_ENCHANT")
        StaticPopup_Hide("BIND_ENCHANT")
    end
    if dirty and db then
        dirty = false
        Refresh()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_AUTODESTROY1 = "/ad"
SLASH_AUTODESTROY2 = "/autodestroy"
SlashCmdList["AUTODESTROY"] = function(msg)
    if not active then
        Print("Inactive: this character has no Inscription, Jewelcrafting or Enchanting.")
        return
    end
    msg = string.lower(msg or "")
    local cmd, arg = string.match(msg, "^(%S*)%s*(.-)$")

    if cmd == "mill" then
        db.mill = not db.mill; Print("Milling " .. OnOff(db.mill))
    elseif cmd == "prospect" then
        db.prospect = not db.prospect; Print("Prospecting " .. OnOff(db.prospect))
    elseif cmd == "de" or cmd == "disenchant" then
        db.disenchant = not db.disenchant; Print("Disenchanting " .. OnOff(db.disenchant))
    elseif cmd == "quality" then
        local q = tonumber(arg)
        if q and q >= 2 and q <= 4 then
            db.maxQuality = q; Print("Disenchanting up to " .. QNAME[q])
        else
            Print("/ad quality 2 (green), 3 (blue) or 4 (epic)"); return
        end
    elseif cmd == "soulbound" then
        db.soulbound = not db.soulbound
        Print("Soulbound items " .. OnOff(db.soulbound))
    elseif cmd == "loot" then
        db.autoloot = not db.autoloot; Print("Auto loot " .. OnOff(db.autoloot))
    elseif cmd == "accept" then
        db.autoaccept = not db.autoaccept; Print("Auto-accept enchant confirmations " .. OnOff(db.autoaccept))
    elseif cmd == "ignore" or cmd == "skip" then
        if current then
            db.ignore[current.id] = true
            Print(current.link .. " removed. Shift+click it in the list to add it back.")
        else
            Print("No item selected."); return
        end
    elseif cmd == "clear" then
        db.ignore = {}; Print("All removed items added back.")
    elseif cmd == "list" then
        Scan(); ToggleList(); return
    elseif cmd == "config" or cmd == "options" then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel); return
    elseif cmd == "show" or cmd == "hide" or cmd == "toggle" then
        if InCombatLockdown() then Print("Not possible in combat."); return end
        if cmd == "toggle" then db.shown = not db.shown else db.shown = (cmd == "show") end
        Print("Button " .. OnOff(db.shown))
    elseif cmd == "reset" then
        if InCombatLockdown() then Print("Not possible in combat."); return end
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
        Print("Button position reset.")
    else
        Print("Commands:")
        Print("/ad config - open the options (keybind, toggles)")
        Print("/ad list - open the item list")
        Print("/ad mill | prospect | de - toggle (" .. OnOff(db.mill) .. " / " .. OnOff(db.prospect) .. " / " .. OnOff(db.disenchant) .. ")")
        Print("/ad quality 2-4 - disenchant up to (" .. QNAME[db.maxQuality] .. ")")
        Print("/ad soulbound - include soulbound items (" .. OnOff(db.soulbound) .. ")")
        Print("/ad loot - auto loot (" .. OnOff(db.autoloot) .. ")")
        Print("/ad accept - auto-accept enchant confirmations (" .. OnOff(db.autoaccept) .. ")")
        Print("/ad ignore - remove the shown item, /ad clear - add all back")
        Print("/ad show | hide | reset - show/hide the button, reset its position")
        return
    end
    dirty = true
end
