-- obsidian-tools/init.lua
-- A Neovim plugin for Obsidian vault management, including backlink following, tag/backlink search,
-- image/audio handling, daily note creation, and template processing.

local M = {}

-- Default configuration
M.config = {
    obsidian_vault_path = "", -- Path to Obsidian vault
    music_folder = "",        -- Path to music folder
    template_path = "",       -- Path to template file (e.g., Templates/Yaml-Template.md)
    debug = false,            -- Enable debug printing
}

-- Helper function to log debug messages
local function debug_print(...)
    if M.config.debug then
        print(...)
    end
end

-- Setup function for user configuration
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
    -- Validate required paths
    if M.config.obsidian_vault_path == "" then
        vim.notify("obsidian-tools: obsidian_vault_path must be set in setup()", vim.log.levels.ERROR)
        return
    end
    if M.config.template_path == "" then
        vim.notify("obsidian-tools: template_path must be set in setup()", vim.log.levels.WARN)
    end
    -- Set global variables for compatibility with original code
    _G.Obsidian_valt_main_path = M.config.obsidian_vault_path
    _G.musik_folder = M.config.music_folder
    -- Setup keymappings
    M.setup_keymaps()
end

-- Keymap helper
local function map(mode, lhs, rhs, opts)
    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { noremap = true, silent = true }, opts or {}))
end

-- Setup keymappings
function M.setup_keymaps()
    local defaults = { noremap = true, silent = true }
    map("n", "<C-q>", "<cmd>:q<CR>", defaults) -- Exit
    map("n", "<leader>f", "<cmd>:Telescope find_files<CR>", defaults) -- Find files
    map("n", "<leader>t", "<cmd>:Neotree<CR>", defaults) -- Open Neotree
    map("n", "<leader>nt", "<cmd>:lua require('obsidian-tools').process_template()<CR>", defaults) -- Apply template
    map("n", "<leader>oot", "<cmd>:lua require('obsidian-tools').create_daily_file(os.date('%Y-%m-%d'))<CR>", defaults) -- Today's note
    map("n", "<leader>ooy", "<cmd>:lua require('obsidian-tools').create_daily_file(require('obsidian-tools').get_yesterday(os.date('%Y-%m-%d')))<CR>", defaults) -- Yesterday's note
    map("n", "<leader>ooT", "<cmd>:lua require('obsidian-tools').create_daily_file(require('obsidian-tools').get_tomorrow(os.date('%Y-%m-%d')))<CR>", defaults) -- Tomorrow's note
    map("n", "<leader>ot", "<cmd>:Easypick tags<CR>", defaults) -- Tag search
    map("n", "<leader>ob", "<cmd>:lua require('obsidian-tools').get_current_backlinks()<CR>", defaults) -- Backlink search
    map("n", "<Enter>", "<cmd>:lua require('obsidian-tools').auto_detect()<CR>", defaults) -- Auto-detect link
    map("n", "<C-p>", "<cmd>:lua require('obsidian-tools').auto_detect()<CR>", defaults) -- Auto-detect link
end

-- Utility function to sanitize SQL input
function M.sanitize_sql_injection(source)
    if not source then return nil end
    return string.gsub(source, "'", "''")
end

-- Read file content, excluding frontmatter
function M.read_file_content(file_path)
    local file_lines = {}
    local file = io.open(file_path, "r")
    if not file then return {} end

    local in_frontmatter = false
    local content_started = false
    for line in file:lines() do
        if line:match("^%-%-%-%s*$") then
            if not in_frontmatter then
                in_frontmatter = true
            else
                in_frontmatter = false
                content_started = true
            end
        elseif not in_frontmatter and content_started then
            table.insert(file_lines, line)
        elseif not in_frontmatter and not content_started and not line:match("^%s*$") then
            table.insert(file_lines, line)
        end
    end
    file:close()
    return file_lines
end

-- Check if file exists
function M.file_exists(name)
    local f = io.open(name, "r")
    return f ~= nil and io.close(f)
end

-- Get yesterday's date
function M.get_yesterday(date_format)
    local year, month, day = date_format:match("(%d+)-(%d+)-(%d+)")
    local timestamp = os.time({ year = year, month = month, day = day })
    local yesterday_timestamp = timestamp - 24 * 60 * 60
    return os.date("%Y-%m-%d", yesterday_timestamp)
end

-- Get tomorrow's date
function M.get_tomorrow(date_format)
    local year, month, day = date_format:match("(%d+)-(%d+)-(%d+)")
    local timestamp = os.time({ year = year, month = month, day = day })
    local tomorrow_timestamp = timestamp + 24 * 60 * 60
    return os.date("%Y-%m-%d", tomorrow_timestamp)
end

-- Process template
function M.process_template()
    local template_path = M.config.template_path .. "/Yaml-Template.md"
    local template_file, err = io.open(template_path, "r")
    if not template_file then
        vim.notify("Could not open template file: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return false
    end

    local template_content = template_file:read("*all")
    template_file:close()

    local current_date = os.date("%Y-%m-%d")
    local current_time = os.date("%H:%M:%S")
    local current_file = vim.api.nvim_buf_get_name(0)
    local title = vim.fn.fnamemodify(current_file, ":t:r")

    local processed_content = template_content:gsub("{{date}}", current_date)
    processed_content = processed_content:gsub("{{time}}", current_time)
    processed_content = processed_content:gsub("{{title}}", title)

    local current_buffer = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(current_buffer, 0, -1, false)
    local current_content = table.concat(lines, '\n')
    local new_content = processed_content .. current_content

    local new_lines = {}
    for line in new_content:gmatch("[^\r\n]+") do
        table.insert(new_lines, line)
    end

    vim.api.nvim_buf_set_lines(current_buffer, 0, -1, false, new_lines)
    return true
end

-- Create daily note
function M.create_daily_file(date_format)
    local file_path = M.config.obsidian_vault_path .. "Every day info/" .. date_format .. ".md"
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
    debug_print("File created at: " .. file_path)
end

-- Sanitize backlink
function M.sanitize_backlink(backlink)
    if not backlink then return nil end
    backlink = string.gsub(backlink, "#.*$", "")
    backlink = string.gsub(backlink, "|.*$", "")
    backlink = string.gsub(backlink, "^-", "")
    backlink = string.gsub(backlink, "^%s*(.-)%s*$", "%1")
    if not string.match(backlink, "%.%w+$") then
        backlink = backlink .. ".md"
    end
    return backlink
end

-- Auto-detect and handle wikilinks
function M.auto_detect()
    local content = M.wikilink_detect_on_cursor()
    if not content then return end
    local sanitized_content = M.sanitize_backlink(content)
    local file_extension = sanitized_content:match(".*%.(.*)$")
    local search = M.find_wikilink(content)

    if file_extension == "md" then
        if search == "" then
            if string.match(content, "%.md$") then
                vim.cmd("edit " .. vim.fn.fnameescape(M.config.obsidian_vault_path .. content))
            else
                vim.cmd("edit " .. vim.fn.fnameescape(M.config.obsidian_vault_path .. content .. ".md"))
            end
        else
            vim.cmd("edit " .. vim.fn.fnameescape(M.config.obsidian_vault_path .. search))
        end
    elseif file_extension == "avif" or file_extension == "png" or file_extension == "jpg" then
        vim.api.nvim_command(":terminal timg ./" .. vim.fn.shellescape(search))
    else
        M.play_audio(M.get_ripgrep(M.config.music_folder, content), content)
    end
end

-- Telescope picker for attributes
function M.pick_attribute(text, callback)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local attributes = {}
    for attribute in text:gmatch("[^\r\n]+") do
        table.insert(attributes, attribute)
    end

    pickers.new({}, {
        prompt_title = "Pick an Attribute",
        finder = finders.new_table { results = attributes },
        sorter = require("telescope.config").values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                debug_print("Selected Attribute:", selection[1])
                callback(selection[1])
            end)
            return true
        end,
    }):find()
end

-- Fallback picker if Telescope is not available
function M.pick_attribute2(text, callback)
    local attributes = {}
    for attribute in text:gmatch("[^\r\n]+") do
        table.insert(attributes, attribute)
    end
    if #attributes > 0 then
        debug_print("Selected Attribute (fallback):", attributes[1])
        callback(attributes[1])
    end
end

-- Get current backlinks
function M.get_current_backlinks()
    local on_cursor = M.wikilink_detect_on_cursor()
    if not on_cursor then
        on_cursor = M.remove_string(vim.fn.expand("%:p"), M.config.obsidian_vault_path)
    else
        on_cursor = M.find_wikilink(on_cursor)
    end
    local query = "SELECT DISTINCT f.path AS full_path FROM backlinks b JOIN files f ON b.file_id = f.id JOIN files fp ON b.backlink_id = fp.id WHERE fp.path LIKE '%" .. M.sanitize_sql_injection(on_cursor:match("([^\n]*)")) .. "%';"
    local text = M.do_sqlite_all(query)
    debug_print(text)
    local edit_md = function(content)
        vim.cmd("edit " .. vim.fn.fnameescape(M.config.obsidian_vault_path .. content))
    end
    if _G.libsAreWorking then
        M.pick_attribute(text, edit_md)
    else
        M.pick_attribute2(text, edit_md)
    end
end

-- Remove string part
function M.remove_string(full_path, part_to_remove)
    local escaped_part = part_to_remove:gsub("([^%w])", "%%%1")
    return full_path:gsub(escaped_part, "")
end

-- Run bash script and save
function M.run_bash_script_and_save()
    vim.cmd("write")
    local current_file_path = vim.fn.expand("%:p")
    local script_path = "markdown-scanner \"" .. current_file_path .. "\" \"" .. M.config.obsidian_vault_path .. "\""
    local output = vim.fn.system(script_path)
    debug_print(output .. "THIS IS RUST BABY")
end

-- Wikilink string finder
function M.wikilink_string_finder(line, cursor_pos)
    local b = 1
    while true do
        local start_pos, end_pos, content = line:find("%[%[([^%[%]]+)%]%]", b)
        if content == nil then break end
        if start_pos and cursor_pos > start_pos and cursor_pos <= end_pos then
            return content
        end
        b = end_pos + 1
    end
end

-- Detect wikilink under cursor
function M.wikilink_detect_on_cursor()
    local line = vim.api.nvim_get_current_line()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)[2] + 1
    return M.wikilink_string_finder(line, cursor_pos)
end

-- Ripgrep search
function M.get_ripgrep(folder, url)
    local handle = io.popen('rg --files "' .. folder .. '" | rg "' .. url .. '" -F')
    local result = handle:read("*a")
    handle:close()
    return result:sub(1, -2)
end

-- Get SQL tags
function M.get_sql_tags(tag)
    local text = 'sqlite3 "' .. M.config.obsidian_vault_path .. 'markdown_data.db" "SELECT f.path FROM files f JOIN file_tags ft ON f.id = ft.file_id JOIN tags t ON ft.tag_id = t.id WHERE t.tag=\'' .. M.sanitize_sql_injection(tag) .. '\';"'
    local edit_md = function(content)
        vim.cmd("edit " .. vim.fn.fnameescape(M.config.obsidian_vault_path .. content))
    end
    if _G.libsAreWorking then
        M.pick_attribute(M.do_sql(text), edit_md)
    else
        M.pick_attribute2(M.do_sql(text), edit_md)
    end
end

-- Execute SQL command
function M.do_sql(search_cmd)
    local handle = io.popen(search_cmd)
    local result = handle:read("*a")
    handle:close()
    return result
end

-- Execute SQL one-liner
function M.do_sql_one_liner(search_cmd)
    local result = M.do_sql(search_cmd)
    return result:sub(1, -2)
end

-- Execute SQLite query
function M.do_sqlite_all(sql)
    local search_cmd = 'sqlite3 "' .. M.config.obsidian_vault_path .. 'markdown_data.db" "' .. sql .. '"'
    return M.do_sql(search_cmd)
end

-- Find wikilink
function M.find_wikilink(content)
    local search_cmd = 'sqlite3 "' .. M.config.obsidian_vault_path .. 'markdown_data.db" "SELECT DISTINCT f.path AS full_path FROM backlinks b JOIN files f ON b.backlink_id = f.id WHERE b.backlink=\'' .. M.sanitize_sql_injection(content) .. '\';"'
    return M.do_sql_one_liner(search_cmd)
end

-- Image finder
function M.my_image_finder()
    local content = M.wikilink_detect_on_cursor()
    if content then
        vim.api.nvim_command(":terminal timg " .. vim.fn.shellescape(M.find_wikilink(content)))
    end
end

-- Music finder
function M.my_music_finder()
    local content = M.wikilink_detect_on_cursor()
    if content then
        M.play_audio(M.get_ripgrep(M.config.music_folder, content), content)
    end
end

-- Edit wikilink content
function M.edit_wikilink_content()
    local content = M.wikilink_detect_on_cursor()
    if content then
        vim.cmd("edit " .. vim.fn.fnameescape(M.config.obsidian_vault_path .. M.find_wikilink(content)))
    end
end

-- Variable to hold VLC process ID
local job_pid = nil

-- Play audio
function M.play_audio(link, url)
    if job_pid ~= nil then
        M.stop_audio()
    end
    debug_print("Playing: " .. url)
    local cmd = 'vlc -I rc "' .. link .. '" > /dev/null 2>&1'
    job_pid = vim.fn.jobstart(cmd, {
        cwd = M.config.obsidian_vault_path,
        on_exit = function() M.stop_audio() end,
    })
end

-- Stop audio
function M.stop_audio()
    if job_pid ~= nil then
        vim.fn.jobstop(job_pid)
        job_pid = nil
    end
end

return M
