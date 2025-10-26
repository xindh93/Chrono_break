-- Loader snippet for the Moon Animator 2 plugin toolbar button.
-- Requiring this module from the plugin's main script ensures that the button
-- is created with a stable, non-empty identifier, preventing duplicate ID errors
-- when Studio reloads the plugin.

local ToolbarUtils = require(script.Parent.ToolbarUtils)

local BUTTON_ID = "MoonAnimator2MainButton"
local TOOLBAR_ID = "Moon Animator 2"
local TOOLTIP = "Open Moon Animator 2"
local ICON = "rbxassetid://0"

return function(pluginInstance)
    if not plugin then
        return nil
    end

    local button = ToolbarUtils.getSingletonButton(pluginInstance, TOOLBAR_ID, BUTTON_ID, TOOLTIP, ICON)
    return button
end
