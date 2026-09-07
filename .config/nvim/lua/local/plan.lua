-- Renders the comment threads of PLAN.md as a readable back-and-forth.
-- Depth marks who spoke: `>` the user, `>> Claude:` Claude, `>>>` the user again.

local _M = {}

-- A quoted line: the run of leading `>` markers, then the body.
local QUOTE = "^(>+)%s?(.*)$"

-- Every extmark we draw lives here, and is thrown away wholesale on redraw.
local ns = vim.api.nvim_create_namespace("local.plan")

local BAR = "▎"

local HL = {
    user = "PlanThreadUser",
    claude = "PlanThreadClaude",
}

-- Line background, one tint per author.
local BG = {
    user = "PlanThreadBgUser",
    claude = "PlanThreadBgClaude",
}

-- The `You:` / `Claude:` label at the head of a message.
local AUTHOR_HL = {
    user = "PlanThreadAuthorUser",
    claude = "PlanThreadAuthorClaude",
}

local LABEL = {
    user = "You: ",
    claude = "Claude: ",
}

-- How much of the author's own color the line background carries.
local TINT = 0.15

-- Buffers we currently decorate, so conceal is only restored where we set it.
local rendered = {}

local function blend(base, over, alpha)
    local function channel(shift)
        local b = math.floor(base / shift) % 256
        local o = math.floor(over / shift) % 256
        return math.floor(b + (o - b) * alpha + 0.5)
    end
    return channel(65536) * 65536 + channel(256) * 256 + channel(1)
end

-- A background a step away from Normal, carrying a little of the author's
-- color. Derived rather than borrowed from CursorLine or ColorColumn, both
-- because the four colorschemes in the cycle shade those differently and
-- because one background per author is the point.
local function tinted_background(fg)
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    if normal.bg == nil or fg == nil then
        return nil
    end
    return blend(normal.bg, fg, TINT)
end

-- Diagnostic groups because every colorscheme in the cycle defines them, and
-- they are far apart in hue. `default` so a colorscheme may override them.
local function setup_highlights()
    vim.api.nvim_set_hl(0, HL.user, { link = "DiagnosticInfo", default = true })
    -- Warn, not Hint: two of the four colorschemes make Hint a gray, and
    -- vscode gives Hint and Info the same blue, so Claude would vanish.
    vim.api.nvim_set_hl(0, HL.claude, { link = "DiagnosticWarn", default = true })
    vim.api.nvim_set_hl(0, "PlanThreadWaiting", { link = "Comment", default = true })

    for _, author in ipairs({ "user", "claude" }) do
        local fg = vim.api.nvim_get_hl(0, { name = HL[author], link = false }).fg
        vim.api.nvim_set_hl(0, BG[author], { bg = tinted_background(fg), default = true })
        -- Bold, which a link cannot add on top of the author's color.
        vim.api.nvim_set_hl(0, AUTHOR_HL[author], { fg = fg, bold = true, default = true })
    end
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("local.plan.highlights", { clear = true }),
    callback = setup_highlights,
})

-- Rendered threads are decoration over the real markdown, and typing into that
-- markdown behind the decoration is how you ruin it. The buffer is locked
-- while it is drawn; `:PlanThreads` unlocks it, and a reply lifts it briefly.
local saved_modifiable = {}

local function lock(buf)
    if saved_modifiable[buf] == nil then
        saved_modifiable[buf] = vim.bo[buf].modifiable
    end
    vim.bo[buf].modifiable = false
end

local function unlock(buf)
    if saved_modifiable[buf] == nil then
        return
    end
    vim.bo[buf].modifiable = saved_modifiable[buf]
    saved_modifiable[buf] = nil
end

local saved_conceal = {}

local function conceal_on(win)
    if saved_conceal[win] == nil then
        saved_conceal[win] = {
            conceallevel = vim.api.nvim_get_option_value("conceallevel", { win = win }),
            concealcursor = vim.api.nvim_get_option_value("concealcursor", { win = win }),
        }
    end
    vim.api.nvim_set_option_value("conceallevel", 2, { win = win })
    vim.api.nvim_set_option_value("concealcursor", "nc", { win = win })
end

local function conceal_off(win)
    local saved = saved_conceal[win]
    if saved == nil then
        return
    end
    vim.api.nvim_set_option_value("conceallevel", saved.conceallevel, { win = win })
    vim.api.nvim_set_option_value("concealcursor", saved.concealcursor, { win = win })
    saved_conceal[win] = nil
end

-- Claude opens its messages with an author line. Everything without one
-- alternates from whoever opened the thread, which is the user unless the
-- first message says otherwise.
local function claude_token(body)
    return body:match("^Claude:%s*") or body:match("^C:%s*")
end

local function is_claude_line(probe)
    return claude_token(probe) ~= nil
end

local function resolve_authors(thread)
    local opener = "user"
    local first = thread.messages[1]
    if first ~= nil and first.explicit then
        opener = "claude"
    end

    for _, message in ipairs(thread.messages) do
        if message.explicit then
            message.author = "claude"
        elseif (message.depth - first.depth) % 2 == 0 then
            message.author = opener
        else
            message.author = opener == "user" and "claude" or "user"
        end
        message.explicit = nil
    end
end

--- Scan a buffer into threads.
--- A thread is a run of consecutive quoted lines; inside it, every change of
--- depth starts a new message.
--- Returns a list of
---   { start_line, end_line, messages = { { depth, author, start_line, end_line } } }
--- with 1-based, inclusive line numbers.
function _M.parse(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local threads = {}
    local thread = nil
    local msg = nil

    local function close_message()
        if msg == nil then
            return
        end
        msg.explicit = is_claude_line(msg.probe or "")
        msg.probe = nil
        table.insert(thread.messages, msg)
        msg = nil
    end

    local function close_thread()
        close_message()
        if thread ~= nil then
            resolve_authors(thread)
            table.insert(threads, thread)
            thread = nil
        end
    end

    for i, line in ipairs(lines) do
        local markers, body = line:match(QUOTE)
        if markers == nil then
            close_thread()
        else
            local depth = #markers

            if thread == nil then
                thread = { start_line = i, end_line = i, messages = {} }
            end
            thread.end_line = i

            if msg == nil or msg.depth ~= depth then
                close_message()
                msg = { depth = depth, start_line = i, end_line = i }
            end
            msg.end_line = i

            if msg.probe == nil and body:match("%S") then
                msg.probe = body
            end
        end
    end
    close_thread()

    return threads
end

--- The author speaking at every depth of a thread, so a nested line can draw
--- the bars of the messages it sits under.
local function authors_by_depth(thread)
    local authors = {}
    local deepest = 0

    for _, message in ipairs(thread.messages) do
        authors[message.depth] = message.author
        deepest = math.max(deepest, message.depth)
    end

    -- A depth nobody spoke at only happens on a malformed thread; alternate
    -- through it so the bars still line up.
    for depth = 1, deepest do
        if authors[depth] == nil then
            authors[depth] = authors[depth - 1] == "user" and "claude" or "user"
        end
    end

    return authors
end

--- The tip of a thread: the deepest message, the last one when depths tie.
local function deepest_message(thread)
    local deepest = thread.messages[1]
    for _, message in ipairs(thread.messages) do
        if message.depth >= deepest.depth then
            deepest = message
        end
    end
    return deepest
end

--- Who a thread waits on: whoever did not speak at its deepest message.
function _M.waiting_on(thread)
    return deepest_message(thread).author == "user" and "claude" or "user"
end

-- How much of a quoted line is markers: the `>` run plus the space after it.
local function prefix_width(line, depth)
    if line:sub(depth + 1, depth + 1) == " " then
        return depth + 1
    end
    return depth
end

-- Width of the text area, which a virtual line has to fill itself to carry a
-- background all the way across. Taken from the first window showing the
-- buffer, and redrawn on resize.
local function text_width(buf)
    local win = vim.fn.win_findbuf(buf)[1]
    if win == nil then
        return vim.o.columns
    end
    local info = vim.fn.getwininfo(win)[1]
    return info.width - info.textoff
end

--- The blank line between two messages: the rails of the depth they have in
--- common, and the background of the message it closes, so the thread reads as
--- one panel rather than two.
local function gap_line(previous, next_message, authors, width)
    local depth = math.min(previous.depth, next_message.depth)
    local chunks = {}

    for level = 1, depth do
        table.insert(chunks, { BAR .. " ", { HL[authors[level]], BG[previous.author] } })
    end
    table.insert(chunks, { string.rep(" ", math.max(0, width - depth * 2)), BG[previous.author] })

    return chunks
end

--- Where a message's `You:` / `Claude:` label goes, and which line that label
--- makes redundant.
--- A bare `Claude:` line carries nothing of its own, so when the message
--- continues below it that line is dropped and the label moves down onto the
--- first line that actually says something.
local function label_target(message, lines)
    local first = lines[message.start_line]
    local body = first:sub(prefix_width(first, message.depth) + 1)
    local token = claude_token(body)

    if token ~= nil and #token == #body and message.end_line > message.start_line then
        return message.start_line + 1, message.start_line
    end
    return message.start_line, nil
end

--- The next (`step` 1) or previous (`step` -1) thread relative to a line.
--- From inside a thread, going back finds that thread itself. Off either end
--- it wraps, so a round of feedback can be walked in circles.
local function step_thread(threads, line, step)
    local target = nil
    for _, thread in ipairs(threads) do
        if step > 0 and thread.start_line > line then
            target = target or thread
        elseif step < 0 and thread.start_line < line then
            target = thread
        end
    end

    if target == nil then
        target = step > 0 and threads[1] or threads[#threads]
    end
    return target
end

local function no_thread()
    vim.notify("No threads in this buffer", vim.log.levels.INFO)
end

--- Jump to the first line of the next or previous thread.
function _M.goto_thread(step)
    local buf = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1]

    local target = step_thread(_M.parse(buf), line, step)
    if target == nil then
        no_thread()
        return
    end

    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { target.start_line, 0 })
end

local function set_keymaps(buf)
    vim.keymap.set("n", "]t", function() _M.goto_thread(1) end,
        { buffer = buf, desc = "Next plan thread" })
    vim.keymap.set("n", "[t", function() _M.goto_thread(-1) end,
        { buffer = buf, desc = "Previous plan thread" })
    vim.keymap.set("n", "<CR>", function() _M.reply() end,
        { buffer = buf, desc = "Reply to plan thread" })
end

local function del_keymaps(buf)
    pcall(vim.keymap.del, "n", "]t", { buffer = buf })
    pcall(vim.keymap.del, "n", "[t", { buffer = buf })
    pcall(vim.keymap.del, "n", "<CR>", { buffer = buf })
end

--- Draw the threads of a buffer: markers concealed, one colored bar per depth
--- in their place, the body indented under it.
function _M.render(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    _M.clear(buf)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line_width = text_width(buf)

    for _, thread in ipairs(_M.parse(buf)) do
        local authors = authors_by_depth(thread)

        -- Threads waiting on Claude need nothing from us, so they stay quiet.
        -- `combine` so the label sits on the line background instead of
        -- replacing it.
        -- On the first line still on screen: a thread Claude opened starts
        -- with a bare `Claude:` line, which we hide.
        local waiting = _M.waiting_on(thread)
        local head = label_target(thread.messages[1], lines)
        vim.api.nvim_buf_set_extmark(buf, ns, head - 1, 0, {
            virt_text = waiting == "user"
                and { { "  waiting on you", HL.user } }
                or { { "  waiting on Claude", "PlanThreadWaiting" } },
            virt_text_pos = "eol",
            hl_mode = "combine",
        })

        for index, message in ipairs(thread.messages) do
            -- Breathing room between messages. Hung below the previous
            -- message, whose last line is always on screen, rather than above
            -- this one, whose first line may be a hidden `Claude:`.
            if index > 1 then
                local previous = thread.messages[index - 1]
                vim.api.nvim_buf_set_extmark(buf, ns, previous.end_line - 1, 0, {
                    virt_lines = { gap_line(previous, message, authors, line_width) },
                })
            end

            local bars = {}
            for depth = 1, message.depth do
                table.insert(bars, { BAR .. " ", HL[authors[depth]] })
            end

            local label_line, hidden_line = label_target(message, lines)

            for lnum = message.start_line, message.end_line do
                local line = lines[lnum]
                local width = prefix_width(line, message.depth)

                vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
                    line_hl_group = BG[message.author],
                })

                if lnum == hidden_line then
                    vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
                        conceal_lines = "",
                    })
                else
                    local virt = vim.list_slice(bars, 1, #bars)

                    if lnum == label_line then
                        -- Hide a literal `Claude:`, the label says it already.
                        local token = claude_token(line:sub(width + 1))
                        if token ~= nil then
                            width = width + #token
                        end
                        table.insert(virt, { LABEL[message.author], AUTHOR_HL[message.author] })
                    end

                    vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
                        end_col = width,
                        conceal = "",
                    })
                    vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
                        virt_text = virt,
                        virt_text_pos = "inline",
                        hl_mode = "combine",
                    })
                end
            end
        end
    end

    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        conceal_on(win)
    end
    set_keymaps(buf)
    lock(buf)
    rendered[buf] = true
end

--- Throw the decoration away.
function _M.clear(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

    if rendered[buf] then
        for _, win in ipairs(vim.fn.win_findbuf(buf)) do
            conceal_off(win)
        end
        del_keymaps(buf)
        unlock(buf)
        rendered[buf] = nil
    end
end

local function thread_at(threads, line)
    for _, thread in ipairs(threads) do
        if line >= thread.start_line and line <= thread.end_line then
            return thread
        end
    end
    return nil
end

--- The thread as prose: markers and `Claude:` stripped, one label per message.
--- Flat, not indented by depth: the panel shows one thread at a time, where
--- depth says nothing the labels and the order do not already say.
--- Returns the lines, and one block per message carrying the rows it occupies,
--- so the panel can tint and label them the way the plan buffer does.
local function unquoted(thread, lines)
    local out = {}
    local blocks = {}

    for index, message in ipairs(thread.messages) do
        if index > 1 then
            table.insert(out, "")
        end

        local body = {}
        for lnum = message.start_line, message.end_line do
            local line = lines[lnum]
            local text = line:sub(prefix_width(line, message.depth) + 1)
            local token = claude_token(text)
            if token ~= nil then
                text = text:sub(#token + 1)
            end
            table.insert(body, text)
        end

        -- A bare `Claude:` line leaves nothing behind; the label speaks for it.
        while body[1] ~= nil and body[1]:match("^%s*$") do
            table.remove(body, 1)
        end
        if body[1] == nil then
            body[1] = ""
        end

        local label = LABEL[message.author]
        local first = #out

        for offset, text in ipairs(body) do
            local prefix = offset == 1 and label or ""
            table.insert(out, text == "" and vim.trim(prefix) or (prefix .. text))
        end

        table.insert(blocks, {
            first = first,
            last = #out - 1,
            author = message.author,
            label_col = 0,
            label_len = #label,
        })
    end

    return out, blocks
end
--- Add a reply to `thread` at the next depth, after its last line.
local function insert_reply(buf, thread, text)
    local markers = string.rep(">", deepest_message(thread).depth + 1)

    local quoted = {}
    for _, line in ipairs(text) do
        table.insert(quoted, line == "" and markers or (markers .. " " .. line))
    end

    local locked = not vim.bo[buf].modifiable
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, thread.end_line, thread.end_line, false, quoted)
    vim.bo[buf].modifiable = not locked
end

-- The sidebar: one at a time, holding the thread the cursor is in and a box to
-- answer it with. Anchored to the thread's first line, re-resolved on every
-- write, because the plan buffer keeps moving under it.
local panel = nil

local function panel_alive()
    return panel ~= nil
        and vim.api.nvim_win_is_valid(panel.thread_win)
        and vim.api.nvim_win_is_valid(panel.input_win)
end

local function panel_close()
    if panel == nil then
        return
    end

    local doomed = panel
    panel = nil

    pcall(vim.api.nvim_del_augroup_by_id, doomed.group)
    for _, win in ipairs({ doomed.thread_win, doomed.input_win }) do
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    for _, buf in ipairs({ doomed.thread_buf, doomed.input_buf }) do
        if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end

--- Draw a thread into the panel, in the colors the plan buffer uses.
local function panel_fill(thread)
    local lines = vim.api.nvim_buf_get_lines(panel.source, 0, -1, false)
    local body, blocks = unquoted(thread, lines)

    vim.bo[panel.thread_buf].modifiable = true
    vim.api.nvim_buf_set_lines(panel.thread_buf, 0, -1, false, body)
    vim.bo[panel.thread_buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(panel.thread_buf, ns, 0, -1)
    for _, block in ipairs(blocks) do
        for row = block.first, block.last do
            vim.api.nvim_buf_set_extmark(panel.thread_buf, ns, row, 0, {
                line_hl_group = BG[block.author],
            })
        end
        vim.api.nvim_buf_set_extmark(panel.thread_buf, ns, block.first, block.label_col, {
            end_col = block.label_col + block.label_len,
            hl_group = AUTHOR_HL[block.author],
        })
    end

    local waiting = _M.waiting_on(thread) == "user" and "waiting on you" or "waiting on Claude"
    vim.wo[panel.thread_win].winbar = string.format("  thread at line %d   %s", thread.start_line, waiting)
    vim.wo[panel.input_win].winbar = string.format("  reply at depth %d   <CR> send   q close",
        deepest_message(thread).depth + 1)

    panel.anchor = thread.start_line
end

--- The thread the panel is pinned to, found again in the current buffer.
local function panel_thread()
    if panel == nil or panel.anchor == nil then
        return nil
    end
    return thread_at(_M.parse(panel.source), panel.anchor)
end

--- Show whatever thread the cursor sits in. A cursor outside every thread
--- leaves the last one up, so the panel keeps saying what it will reply to.
local function panel_follow()
    if not panel_alive() then
        panel_close()
        return
    end

    local line = vim.api.nvim_win_get_cursor(0)[1]
    local thread = thread_at(_M.parse(panel.source), line)
    if thread ~= nil then
        panel_fill(thread)
    end
end

local function panel_send()
    local text = vim.api.nvim_buf_get_lines(panel.input_buf, 0, -1, false)
    while text[1] ~= nil and text[1]:match("^%s*$") do
        table.remove(text, 1)
    end
    while text[#text] ~= nil and text[#text]:match("^%s*$") do
        table.remove(text)
    end

    if #text == 0 then
        vim.notify("Empty reply, nothing written", vim.log.levels.INFO)
        return
    end

    local thread = panel_thread()
    if thread == nil then
        vim.notify("That thread is no longer in the buffer", vim.log.levels.WARN)
        return
    end

    insert_reply(panel.source, thread, text)
    vim.api.nvim_buf_set_lines(panel.input_buf, 0, -1, false, {})

    if rendered[panel.source] then
        _M.render(panel.source)
    end
    panel_fill(thread_at(_M.parse(panel.source), thread.start_line))
end

--- Walk threads without leaving the panel: the plan window's cursor moves with
--- it, so the two views keep pointing at the same thread.
local function panel_step(step)
    if not panel_alive() then
        return
    end

    local target = step_thread(_M.parse(panel.source), panel.anchor or 0, step)
    if target == nil then
        no_thread()
        return
    end

    for _, win in ipairs(vim.fn.win_findbuf(panel.source)) do
        if win ~= panel.thread_win and win ~= panel.input_win then
            vim.api.nvim_win_set_cursor(win, { target.start_line, 0 })
        end
    end
    panel_fill(target)
end

local function panel_focus_source()
    for _, win in ipairs(vim.fn.win_findbuf(panel.source)) do
        if win ~= panel.thread_win and win ~= panel.input_win then
            vim.api.nvim_set_current_win(win)
            return
        end
    end
end

local function panel_focus_input()
    vim.api.nvim_set_current_win(panel.input_win)
    vim.cmd("startinsert")
end

--- Open the sidebar for the buffer, without leaving it.
local function panel_open(buf)
    local source_win = vim.api.nvim_get_current_win()

    local thread_buf = vim.api.nvim_create_buf(false, true)
    local input_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[input_buf].filetype = "markdown"
    pcall(vim.api.nvim_buf_set_name, thread_buf, "plan://thread")
    pcall(vim.api.nvim_buf_set_name, input_buf, "plan://reply")

    local width = math.min(60, math.max(40, math.floor(vim.o.columns * 0.35)))
    local thread_win = vim.api.nvim_open_win(thread_buf, false, {
        split = "right",
        win = source_win,
        width = width,
    })
    local input_win = vim.api.nvim_open_win(input_buf, false, {
        split = "below",
        win = thread_win,
        height = 6,
    })

    for _, win in ipairs({ thread_win, input_win }) do
        vim.wo[win].number = false
        vim.wo[win].relativenumber = false
        vim.wo[win].signcolumn = "no"
        vim.wo[win].wrap = true
        vim.wo[win].winfixwidth = true
    end

    panel = {
        source = buf,
        thread_buf = thread_buf,
        input_buf = input_buf,
        thread_win = thread_win,
        input_win = input_win,
        group = vim.api.nvim_create_augroup("local.plan.panel", { clear = true }),
    }

    vim.keymap.set("n", "<CR>", panel_send, { buffer = input_buf, desc = "Send reply" })
    vim.keymap.set({ "n", "i" }, "<C-s>", panel_send, { buffer = input_buf, desc = "Send reply" })
    vim.keymap.set("n", "<Esc>", panel_focus_source, { buffer = input_buf, desc = "Back to the plan" })
    for _, scratch in ipairs({ thread_buf, input_buf }) do
        vim.keymap.set("n", "q", panel_close, { buffer = scratch, desc = "Close the thread panel" })
        vim.keymap.set("n", "]t", function() panel_step(1) end,
            { buffer = scratch, desc = "Next plan thread" })
        vim.keymap.set("n", "[t", function() panel_step(-1) end,
            { buffer = scratch, desc = "Previous plan thread" })
    end
    vim.keymap.set("n", "<CR>", panel_focus_input, { buffer = thread_buf, desc = "Reply" })

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = panel.group,
        buffer = buf,
        callback = panel_follow,
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = panel.group,
        buffer = buf,
        callback = function()
            local thread = panel_thread()
            if thread ~= nil then
                panel_fill(thread)
            end
        end,
    })
    -- Someone closing half the panel by hand closes the rest of it.
    vim.api.nvim_create_autocmd("WinClosed", {
        group = panel.group,
        callback = function(args)
            local win = tonumber(args.match)
            if panel ~= nil and (win == panel.thread_win or win == panel.input_win) then
                vim.schedule(panel_close)
            end
        end,
    })

    panel_follow()
end

--- Toggle the sidebar for the current buffer.
function _M.panel(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if panel_alive() then
        panel_close()
    else
        panel_close()
        panel_open(buf)
    end
end

--- Reply to the thread under the cursor: open the sidebar if it is closed,
--- then drop into the box with the thread already loaded.
function _M.reply(buf)
    buf = buf or vim.api.nvim_get_current_buf()

    if thread_at(_M.parse(buf), vim.api.nvim_win_get_cursor(0)[1]) == nil then
        vim.notify("Not inside a thread", vim.log.levels.INFO)
        return
    end

    if not panel_alive() then
        panel_close()
        panel_open(buf)
    else
        panel_follow()
    end
    panel_focus_input()
end

--- Dump the parse of a buffer into a scratch split, to eyeball it.
function _M.debug(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local threads = _M.parse(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    local out = {
        string.format("%s: %d thread(s)", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"), #threads),
    }

    for ti, thread in ipairs(threads) do
        table.insert(out, "")
        table.insert(out, string.format("thread %d: lines %d-%d, %d message(s), waiting on %s",
            ti, thread.start_line, thread.end_line, #thread.messages, _M.waiting_on(thread)))

        for mi, message in ipairs(thread.messages) do
            local text = lines[message.start_line]:gsub("^>+%s?", "")
            if #text > 40 then
                text = text:sub(1, 39) .. "…"
            end
            table.insert(out, string.format("  %d. depth %d  %-6s  lines %3d-%-3d  %s",
                mi, message.depth, message.author, message.start_line, message.end_line, text))
        end
    end

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, out)
    vim.bo[scratch].modifiable = false
    vim.bo[scratch].bufhidden = "wipe"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = scratch, silent = true })

    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, scratch)
    vim.api.nvim_win_set_height(0, math.min(#out, 20))
end

-- The gap lines are padded to a fixed width, so they have to be redrawn when
-- that width changes.
vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = vim.api.nvim_create_augroup("local.plan.resize", { clear = true }),
    callback = function()
        for _, buf in ipairs(vim.tbl_keys(rendered)) do
            if vim.api.nvim_buf_is_valid(buf) then
                _M.render(buf)
            end
        end
    end,
})

-- Buffers the toggle turned off, so entering them does not turn it back on.
local off = {}

vim.api.nvim_create_user_command("PlanThreads",
    function()
        local buf = vim.api.nvim_get_current_buf()
        if rendered[buf] then
            _M.clear(buf)
            off[buf] = true
        else
            off[buf] = nil
            _M.render(buf)
        end
    end,
    {
        nargs = 0,
    }
)

vim.api.nvim_create_user_command("PlanPanel",
    function()
        _M.panel()
    end,
    {
        nargs = 0,
    }
)

vim.api.nvim_create_user_command("PlanReply",
    function()
        _M.reply()
    end,
    {
        nargs = 0,
    }
)

-- By filename, not filetype, so ordinary markdown is left alone.
vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("local.plan", { clear = true }),
    pattern = "PLAN.md",
    callback = function(args)
        if not off[args.buf] then
            _M.render(args.buf)
        end
    end,
})

vim.api.nvim_create_user_command("PlanThreadsDebug",
    function()
        _M.debug()
    end,
    {
        nargs = 0,
    }
)

return _M
