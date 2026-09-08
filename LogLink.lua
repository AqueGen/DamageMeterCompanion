local addonName, ns = ...

local Link = ns.Link

local LogLink = {}

-- Retail hands addons "secret" values: a real value the client will not let
-- tainted code compare, match, concatenate or use as a table key. A unit token
-- and a player name from a menu can both arrive that way, and everything below
-- does all four to them.
local function usable(value)
    if value == nil then return false end
    if type(canaccessvalue) ~= "function" then return true end
    local ok, allowed = pcall(canaccessvalue, value)
    return ok and allowed == true
end

-- An addon cannot open a browser. The Lua sandbox has no io, no os.execute and
-- no way to launch anything, by design - which is why every addon that offers a
-- link offers it the same way: a box with the text already selected, for one
-- Ctrl+C.
local POPUP = "DAMAGEMETERCOMPANION_LOGLINK_COPY"
StaticPopupDialogs[POPUP] = {
    text = "%s\n\nCtrl+C to copy, Escape to close.",
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 350,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox
        if not box then return end
        box:SetText(data.url)
        box:HighlightText()
        box:SetFocus()
        -- Escape closes the dialog rather than only unfocusing the box, and
        -- Enter does the same: the box exists to be copied from, never typed
        -- into.
        box:SetScript("OnEscapePressed", function() self:Hide() end)
        box:SetScript("OnEnterPressed", function() self:Hide() end)
        -- A reader who starts typing would otherwise silently replace the link
        -- and copy their own keystrokes.
        box:SetScript("OnTextChanged", function(edit)
            if edit:GetText() ~= data.url then
                edit:SetText(data.url)
                edit:HighlightText()
            end
        end)
    end,
}

---@param name string
---@param realm string|nil
local function show(name, realm)
    if not usable(name) then return end
    if not usable(realm) or realm == "" then realm = GetNormalizedRealmName() end

    local url, problem = Link.For(name, realm, GetCurrentRegion())
    if not url then
        ns.Print(problem or "no link")
        return
    end
    StaticPopup_Show(POPUP, url, nil, { url = url })
end
ns.ShowLogLink = show

-- The name and realm a menu is about. A unit menu carries a token; a chat or
-- friends-list menu carries the name and server as text, and the name it carries
-- may already have the realm attached.
local function targetOf(contextData)
    if not contextData then return nil end

    local unit = contextData.unit
    if usable(unit) and UnitIsPlayer(unit) then
        local name, realm = UnitName(unit)
        if usable(name) then return name, usable(realm) and realm ~= "" and realm or nil end
    end

    local name = contextData.name
    if not usable(name) then return nil end
    local short, realm = string.match(name, "^(.-)%-(.+)$")
    if short then return short, realm end
    return name, usable(contextData.server) and contextData.server or nil
end

-- Every unit menu that can be about another player. Blizzard tags them
-- MENU_UNIT_<TYPE>, one tag per context rather than one for all of them, so the
-- list is written out - a missing tag costs that one menu, never an error.
local MENUS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID", "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_ARENAENEMY",
    "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_GUILD", "MENU_UNIT_CHAT_ROSTER",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_WOW_MEMBER",
    "MENU_UNIT_SELF", "MENU_UNIT_BN_FRIEND",
}

-- A name the game hands over as one string: "Name" on your own realm,
-- "Name-Realm" everywhere else.
local function splitName(fullName)
    if not usable(fullName) then return nil end
    local short, realm = string.match(fullName, "^(.-)%-(.+)$")
    if short then return short, realm end
    return fullName, nil
end

-- The group finder menus pass no contextData at all. The frame the menu belongs
-- to is the only handle on who was clicked, and each list keeps the player in a
-- different place, so one reader per list.
local function applicantOf(owner)
    local memberIdx = owner and owner.memberIdx
    local parent = memberIdx and owner.GetParent and owner:GetParent()
    local applicantID = parent and parent.applicantID
    if not applicantID then return nil end
    return splitName(C_LFGList.GetApplicantMemberInfo(applicantID, memberIdx))
end

local function searchEntryLeaderOf(owner)
    local resultID = owner and owner.resultID
    local info = resultID and C_LFGList.GetSearchResultInfo(resultID)
    if not info then return nil end
    return splitName(info.leaderName)
end

-- Switched off leaves the menus exactly as Blizzard built them, which is the
-- only honest way to be off: a menu entry that appears and refuses is worse
-- than no entry.
local function wanted()
    if not ns.db or ns.db.logLink == false then
        return false
    end
    -- Not in combat, for the same reason the settings entry is out-of-combat
    -- only (Config.lua): an entry of ours is a tainted value in the menu's
    -- description, and Blizzard's layout reads it before measuring the menu
    -- regions, whose rects are Secret in combat (Menu.lua:989-999) -
    -- 'attempt to perform numeric conversion on a secret number value'.
    -- The standalone addon this came from did not gate on combat, and that was
    -- a bug waiting for someone to right-click a raid frame mid-pull.
    return not InCombatLockdown()
end

local function section(rootDescription, name, realm)
    rootDescription:CreateDivider()
    rootDescription:CreateTitle("Warcraft Logs")
    rootDescription:CreateButton(Link.ZONE_NAME, function() show(name, realm) end)
end

local function install()
    if type(Menu) ~= "table" or type(Menu.ModifyMenu) ~= "function" then return end

    for _, tag in ipairs(MENUS) do
        Menu.ModifyMenu(tag, function(_, rootDescription, contextData)
            if not wanted() then return end
            local name, realm = targetOf(contextData)
            if not name then return end
            section(rootDescription, name, realm)
        end)
    end

    -- An applicant to your own listing.
    Menu.ModifyMenu("MENU_LFG_FRAME_MEMBER_APPLY", function(owner, rootDescription)
        if not wanted() then return end
        local name, realm = applicantOf(owner)
        if not name then return end
        section(rootDescription, name, realm)
    end)

    -- A group in the search results, which is about its leader.
    Menu.ModifyMenu("MENU_LFG_FRAME_SEARCH_ENTRY", function(owner, rootDescription)
        if not wanted() then return end
        local name, realm = searchEntryLeaderOf(owner)
        if not name then return end
        section(rootDescription, name, realm)
    end)
end

-- /wcl keeps working with the feature switched off: the switch is about the
-- menus, and a typed command is the player asking for exactly this.
function ns.HandleLogLinkCommand(input)
    local text = string.match(input or "", "^%s*(.-)%s*$")
    if text == "" then
        -- No argument means the current target, which is the common case: you
        -- are looking at somebody and want their page.
        if UnitExists("target") and UnitIsPlayer("target") then
            local name, realm = UnitName("target")
            return show(name, realm)
        end
        ns.Print("/wcl <name>-<realm>, or target a player first")
        return
    end
    -- The first hyphen, not the last: a realm slug routinely contains one and a
    -- character name never can.
    local separator = string.find(text, "-", 1, true)
    if separator then
        show(string.sub(text, 1, separator - 1), string.sub(text, separator + 1))
    else
        show(text, nil)
    end
end

function LogLink.Enable()
    install()

    SLASH_DAMAGEMETERCOMPANIONLOGLINK1 = "/wcl"
    SlashCmdList["DAMAGEMETERCOMPANIONLOGLINK"] = ns.HandleLogLinkCommand
end

ns.RegisterModule("LogLink", LogLink)
