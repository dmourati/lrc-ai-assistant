local LrView = import 'LrView'
local LrBinding = import 'LrBinding'
local LrColor = import 'LrColor'
local LrHttp = import 'LrHttp'

local function sectionsForTopOfDialog(viewFactory, propertyTable)
    
    local bind = LrView.bind
    local share = LrView.share
    
    -- Initialize default values if not set
    if not propertyTable.chatgptApiKey then
        propertyTable.chatgptApiKey = ""
    end
    
    if not propertyTable.assistantId then
        propertyTable.assistantId = "asst_HQan3G9EY0pDEpFaQG97idQL"
    end
    
    return {
        {
            title = "OpenAI Configuration",
            
            viewFactory:row {
                spacing = viewFactory:label_spacing(),
                
                viewFactory:static_text {
                    title = "OpenAI API Key:",
                    alignment = 'right',
                    width = share 'label_width',
                },
                
                viewFactory:password_field {
                    value = bind 'chatgptApiKey',
                    width_in_chars = 50,
                    tooltip = "Enter your OpenAI API key here",
                },
            },
            
            viewFactory:row {
                spacing = viewFactory:label_spacing(),
                
                viewFactory:static_text {
                    title = "",
                    width = share 'label_width',
                },
                
                viewFactory:static_text {
                    title = "Get your API key from: https://platform.openai.com/api-keys",
                    text_color = LrColor("blue"),
                    tooltip = "Click to open OpenAI API keys page",
                    mouse_down = function()
                        if LrHttp and LrHttp.openUrlInBrowser then
                            LrHttp.openUrlInBrowser("https://platform.openai.com/api-keys")
                        end
                    end,
                },
            },
            
            viewFactory:spacer { height = 20 },
            
            viewFactory:row {
                spacing = viewFactory:label_spacing(),
                
                viewFactory:static_text {
                    title = "Assistant ID:",
                    alignment = 'right',
                    width = share 'label_width',
                },
                
                viewFactory:edit_field {
                    value = bind 'assistantId',
                    width_in_chars = 50,
                    tooltip = "OpenAI Assistant ID (default provided)",
                },
            },
            
            viewFactory:spacer { height = 10 },
            
            viewFactory:row {
                spacing = viewFactory:label_spacing(),
                
                viewFactory:static_text {
                    title = "",
                    width = share 'label_width',
                },
                
                viewFactory:static_text {
                    title = "Save your settings and restart Lightroom to ensure changes take effect.",
                    text_color = LrColor("red"),
                },
            },
        }
    }
end

-- This function is called when the plugin manager dialog is opened
local function startDialog(propertyTable)
    -- Initialize property table with defaults if needed
    if not propertyTable.chatgptApiKey then
        propertyTable.chatgptApiKey = ""
    end
    
    if not propertyTable.assistantId then
        propertyTable.assistantId = "asst_HQan3G9EY0pDEpFaQG97idQL"
    end
end

return {
    sectionsForTopOfDialog = sectionsForTopOfDialog,
    startDialog = startDialog,
}
