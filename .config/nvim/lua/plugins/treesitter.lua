local Plugin = {'nvim-treesitter/nvim-treesitter'}

Plugin.branch = 'main'

-- The main branch does not support lazy-loading, and parsers are pinned to
-- plugin revisions, so they have to be rebuilt whenever the plugin updates.
Plugin.lazy = false
Plugin.build = ':TSUpdate'

Plugin.dependencies = {
  {'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main'},
}

Plugin.config = function()
    -- setup() only takes install_dir, and it already defaults to
    -- stdpath('data')/site, so there is nothing to configure.
    require('nvim-treesitter').install({
        "cpp", "javascript", "typescript",
        "c", "lua", "vim", "vimdoc", "go",
    })

    vim.api.nvim_create_autocmd('FileType', {
        callback = function(ev)
            local lang = vim.treesitter.language.get_lang(ev.match)
            -- Only take over indentation when highlighting actually started.
            -- Without a parser indentexpr() returns -1, which would clobber
            -- the indent the built-in ftplugin set up.
            if lang and pcall(vim.treesitter.start, ev.buf, lang) then
                vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end
        end,
    })
end

return Plugin
