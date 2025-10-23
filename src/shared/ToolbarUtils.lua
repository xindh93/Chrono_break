-- Utility helpers for creating plugin toolbar buttons without duplicate IDs.
-- This module guards toolbar/button creation so the Moon Animator 2 plugin can be
-- required multiple times during development without triggering duplicate ID errors.
--
-- Usage:
--   local ToolbarUtils = require(path.to.ToolbarUtils)
--   local button = ToolbarUtils.getSingletonButton(plugin, "Moon Animator 2", "MoonAnimatorToggle",
--       "Open Moon Animator 2", "rbxassetid://0")
--
-- The helper caches the toolbar and button using `_G` so repeated `require` calls reuse
-- the existing instances instead of attempting to create new ones with the same IDs.
-- This prevents errors such as:
--   Cannot create more than one button with id "" in toolbar with id "Moon Animator 2"
--
-- The module also enforces non-empty IDs so accidental empty strings don't sneak back in.

local ToolbarUtils = {}

local function assertNonEmpty(value, name)
    assert(type(value) == "string" and value ~= "", string.format("%s must be a non-empty string", name))
end

local function getToolbarCache()
    _G.__toolbarCache = _G.__toolbarCache or {}
    return _G.__toolbarCache
end

function ToolbarUtils.getSingletonButton(pluginInstance, toolbarId, buttonId, tooltip, icon)
    if not plugin then
        -- When required from a non-plugin context we just bail out quietly.
        return nil
    end

    assert(pluginInstance == plugin, "A valid plugin instance is required")
    assertNonEmpty(toolbarId, "toolbarId")
    assertNonEmpty(buttonId, "buttonId")

    local cache = getToolbarCache()

    local toolbarEntry = cache[toolbarId]
    if not toolbarEntry then
        toolbarEntry = {}
        toolbarEntry.toolbar = plugin:CreateToolbar(toolbarId)
        cache[toolbarId] = toolbarEntry
    end

    if not toolbarEntry.button then
        toolbarEntry.button = toolbarEntry.toolbar:CreateButton(buttonId, tooltip or buttonId, icon or "rbxassetid://0")
    end

    return toolbarEntry.button
end

return ToolbarUtils
