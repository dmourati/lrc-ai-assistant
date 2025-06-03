--[[
BatchSettingsMenu.lua - Menu handler for batch settings
This file is called when user selects "AI Assistant Batch Settings" from Library menu
]]--

local BatchProcessor = require 'BatchProcessor'

-- This is called when the menu item is selected
BatchProcessor.showSettingsDialog()