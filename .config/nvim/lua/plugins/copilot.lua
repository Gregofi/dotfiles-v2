local Plugin = { 'zbirenbaum/copilot.lua' }

Plugin.opts = {
    panel = {
        enabled = false,
        -- defaults here are very dangerous, for example accept swallows enter
        keymap = {
            jump_prev = false,
            jump_next = false,
            accept = false,
            refresh = false,
            open = false
        },
    },
    suggestion = {
        enabled = true,
        auto_trigger = false,
        keymap = {
            accept = "<C-j>",
            accept_word = "<C-h>",
            accept_line = false,

            next = "<C-k>",
            prev = "<C-l>",

            dismiss = false,
            toggle_auto_trigger = false,
        },
    }
}

return Plugin
