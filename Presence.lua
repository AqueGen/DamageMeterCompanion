local addonName, ns = ...

ns.Presence = {}
local Presence = ns.Presence

Presence.STRATA_ORDER = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "FULLSCREEN",
    "FULLSCREEN_DIALOG",
    "TOOLTIP",
}

local hovered = {}

-- Edit Mode's Transparency setting stays the authority for the hovered state.
-- The idle state is a factor of it, so moving that slider keeps working and the
-- two states never drift apart.
function Presence.ComputeAlpha(editModeAlpha, idleFactor, isHovered)
    if isHovered then
        return editModeAlpha
    end

    return editModeAlpha * idleFactor
end

function Presence.ApplyAlpha(window)
    window:SetAlpha(Presence.ComputeAlpha(DamageMeter:GetWindowAlpha(), ns.db.idleAlpha, hovered[window]))
end

function Presence.ApplyAlphaToAll()
    ns.ForEachSessionWindow(Presence.ApplyAlpha)
end

-- The source window template pins frameStrata="HIGH", which overrides
-- inheritance from its parent. Raising the meter without raising it too would
-- push the spell breakdown behind the bars.
function Presence.NextStrataUp(strata)
    for index, name in ipairs(Presence.STRATA_ORDER) do
        if name == strata then
            return Presence.STRATA_ORDER[math.min(index + 1, #Presence.STRATA_ORDER)]
        end
    end

    return "HIGH"
end

-- SetFrameStrata throws on a name it does not know, and the only way to set
-- this before Task 9's dropdown exists is hand-editing the saved variable. An
-- unrecognised value would then error on every reload, so resolve it first.
function Presence.ResolveStrata(strata)
    for _, name in ipairs(Presence.STRATA_ORDER) do
        if name == strata then
            return strata
        end
    end

    return ns.defaults.strata
end

function Presence.ApplyStrata()
    local strata = Presence.ResolveStrata(ns.db.strata)

    DamageMeter:SetFrameStrata(strata)

    ns.ForEachSessionWindow(function(window)
        window:GetSourceWindow():SetFrameStrata(Presence.NextStrataUp(strata))
    end)
end

function Presence.Enable()
    -- OnEnter sets the MouseOver reason; the window's own OnUpdate clears it
    -- once the mouse is off both the window and its resize button. One hook
    -- gives us both edges without an OnUpdate of our own.
    local function OnSetOnUpdateReason(window, reason, enabled)
        if reason ~= "MouseOver" then
            return
        end

        hovered[window] = enabled and true or nil
        Presence.ApplyAlpha(window)
    end

    -- Mixin hook for windows created later, instance hooks for the ones that
    -- already exist and carry their own copy of SetOnUpdateReason.
    hooksecurefunc(DamageMeterSessionWindowMixin, "SetOnUpdateReason", OnSetOnUpdateReason)
    ns.ForEachSessionWindow(function(window)
        ns.HookInstance(window, "SetOnUpdateReason", OnSetOnUpdateReason)
    end)

    -- An Edit Mode transparency change pushes a raw alpha onto every window;
    -- re-apply through our path so the idle state survives it. DamageMeter
    -- already exists, so this is an instance hook.
    ns.HookInstance(DamageMeter, "OnWindowAlphaChanged", Presence.ApplyAlphaToAll)

    Presence.ApplyAlphaToAll()
    Presence.ApplyStrata()
end

ns.RegisterModule("Presence", Presence)
