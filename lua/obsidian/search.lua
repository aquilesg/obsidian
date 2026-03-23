local search = {}

local log = require("obsidian.log")

---@class NoteSearchOpts
---@field query string # Text to search for
---@field folder string | nil # Folder within vault to limit search to

---@param s string
---@param max number
---@return string
local function truncate(s, max)
	if #s <= max then
		return s
	end
	return s:sub(1, max - 1) .. "…"
end

--- Obsidian CLI expects `query="..."` (double quotes around the value). Escape `\` and `"` inside the value only.
---@param s string
---@return string
local function escapeObsidianCliDoubleQuoted(s)
	return (s:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

--- Flatten Obsidian `search:context format=json` payload into selectable rows.
--- Shape: `[{ file = "rel/path.md", matches = { { line = n, text = "..." }, ... } }, ...]`
---@param parsed table
---@return { file: string, line: integer, text: string }[]
local function flatten_search_results(parsed)
	local items = {}
	if type(parsed) ~= "table" then
		return items
	end
	for _, entry in ipairs(parsed) do
		if type(entry) == "table" and type(entry.file) == "string" then
			for _, m in ipairs(entry.matches or {}) do
				items[#items + 1] = {
					file = entry.file,
					line = type(m.line) == "number" and m.line or 1,
					text = type(m.text) == "string" and m.text or "",
				}
			end
		end
	end
	return items
end

--- Run `obsidian search:context format=json` and flatten matches (no picker).
---@param opts NoteSearchOpts
---@return { file: string, line: integer, text: string }[]|nil  nil if CLI failed
local function query_note_matches(opts)
	local searchCmd = "search:context format=json"
	if opts.folder ~= nil and opts.folder ~= "" then
		searchCmd = searchCmd .. " path=" .. vim.fn.shellescape(opts.folder)
	end
	searchCmd = searchCmd .. ' query="' .. escapeObsidianCliDoubleQuoted(opts.query) .. '"'

	local response = require("obsidian.cli").runJsonCommand(searchCmd)
	if response == nil then
		log.append(
			string.format(
				"query_note_matches: runJsonCommand returned nil\nquery=%s\nfolder=%s\n",
				opts.query,
				opts.folder or ""
			)
		)
		return nil
	end
	return flatten_search_results(response)
end

---@param item { file: string, line: integer, text: string }
---@return string
local function format_match_label(item)
	return string.format("%s:%d  %s", item.file, item.line, truncate(item.text:gsub("\n", " "), 100))
end

---@param vault_dir string
---@param item { file: string, line: integer, text: string }
local function open_match_at_line(vault_dir, item)
	local path = vim.fs.joinpath(vault_dir, item.file)
	if vim.fn.filereadable(path) == 0 then
		vim.notify("File not found: " .. path, vim.log.levels.WARN)
		return
	end
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	local line = math.max(1, item.line)
	vim.api.nvim_win_set_cursor(0, { line, 0 })
	vim.cmd("normal! zz")
end

---@class NoteMatchPickerOpts
---@field prompt_title string|nil
---@field results_title string|nil
---@field empty_message string|nil  Shown when the search returns no matches (default: "No matches")

--- Telescope (grep preview) + vim.ui.select fallback for note search matches.
---@param vault_dir string
---@param items { file: string, line: integer, text: string }[]
---@param on_choice fun(item: { file: string, line: integer, text: string })
---@param picker_opts NoteMatchPickerOpts|nil
local function open_note_match_picker(vault_dir, items, on_choice, picker_opts)
	picker_opts = picker_opts or {}
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = picker_opts.prompt_title or "Obsidian search",
			results_title = picker_opts.results_title or "Matches",
			finder = finders.new_table({
				results = items,
				entry_maker = function(match)
					local abs_path = vim.fs.joinpath(vault_dir, match.file)
					return {
						value = match,
						display = format_match_label(match),
						ordinal = match.file .. " " .. match.text,
						path = abs_path,
						lnum = match.line,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.grep_previewer({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection and selection.value then
						on_choice(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

---@param items { file: string, line: integer, text: string }[]
---@param on_choice fun(item: { file: string, line: integer, text: string })
local function open_note_match_ui_select(items, on_choice)
	vim.ui.select(items, {
		prompt = "Obsidian search",
		format_item = format_match_label,
	}, function(choice)
		if choice == nil then
			return
		end
		on_choice(choice)
	end)
end

--- Run search CLI and show the note-match Telescope picker (or ui.select).
---@param vault_dir string
---@param opts NoteSearchOpts
---@param picker_opts NoteMatchPickerOpts|nil
local function run_search_and_pick(vault_dir, opts, picker_opts)
	local p = picker_opts or {}
	local items = query_note_matches(opts)
	if items == nil then
		return
	end
	if #items == 0 then
		vim.notify(p.empty_message or "No matches", vim.log.levels.INFO)
		return
	end

	local function open_choice(choice)
		open_match_at_line(vault_dir, choice)
	end

	local ok, err = pcall(open_note_match_picker, vault_dir, items, open_choice, p)
	if not ok then
		log.append("open_note_match_picker failed: " .. tostring(err) .. "\n")
		vim.notify("Telescope picker failed (" .. tostring(err) .. "). Using vim.ui.select.", vim.log.levels.WARN)
		open_note_match_ui_select(items, open_choice)
	end
end

--- Search within notes for target query; pick a result and open the file at the match line.
---@param opts NoteSearchOpts
search.findWithinNotes = function(opts)
	opts = opts or {}
	if not opts.query or opts.query == "" then
		log.append("findWithinNotes: query is required (empty)\n")
		vim.notify("obsidian search: query is required", vim.log.levels.ERROR)
		return
	end

	local cfg = require("obsidian").getConfig()
	if not cfg.obsidian_vault_dir then
		log.append("findWithinNotes: obsidian_vault_dir not configured\n")
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
		return
	end

	run_search_and_pick(cfg.obsidian_vault_dir, opts, nil)
end

--- Parse `obsidian tags` output: one tag per line (e.g. `#foo`).
---@param text string
---@return string[]
local function parse_tag_lines(text)
	local items = {}
	if not text or text == "" then
		return items
	end
	for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
		line = vim.trim(line)
		if line ~= "" then
			items[#items + 1] = line
		end
	end
	return items
end

---@param tag_line string
---@return string
local function format_tag_label(tag_line)
	return tag_line
end

---@param tags string[]
---@param on_choice fun(tag_line: string)
local function pick_tags_with_telescope(tags, on_choice)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	local tag_picker = previewers.new_buffer_previewer({
		title = "Tag",
		define_preview = function(self, entry, _)
			local tag = entry.value
			local lines = {
				tag,
				"",
				"Press <Enter> to list notes containing this tag.",
			}
			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
			pcall(function()
				require("telescope.previewers.utils").highlighter(self.state.bufnr, "markdown")
			end)
		end,
	})

	pickers
		.new({}, {
			prompt_title = "Obsidian tags",
			results_title = "Tags",
			finder = finders.new_table({
				results = tags,
				entry_maker = function(tag)
					return {
						value = tag,
						display = format_tag_label(tag),
						ordinal = tag,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = tag_picker,
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection and selection.value then
						on_choice(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

---@param tags string[]
---@param on_choice fun(tag_line: string)
local function pick_tags_ui_select(tags, on_choice)
	vim.ui.select(tags, {
		prompt = "Obsidian tags",
		format_item = format_tag_label,
	}, function(choice)
		if choice == nil then
			return
		end
		on_choice(choice)
	end)
end

---@class TagSearchOpts
---@field query string|nil Optional substring filter on tag names (case-insensitive)

--- Populate the tag list from `obsidian tags`, pick a tag in Telescope, then run the same
--- `search:context` query flow and open the note-match picker (files/lines with grep preview).
---@param opts TagSearchOpts|nil
search.findWithinTags = function(opts)
	opts = opts or {}

	local cfg = require("obsidian").getConfig()
	if not cfg.obsidian_vault_dir then
		log.append("findWithinTags: obsidian_vault_dir not configured\n")
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
		return
	end

	local raw = require("obsidian.cli").runTextCommand("tags")
	if raw == nil then
		log.append('findWithinTags: runTextCommand("tags") returned nil\n')
		return
	end

	local tags = parse_tag_lines(raw)
	if opts.query ~= nil and opts.query ~= "" then
		local q = opts.query:lower()
		local filtered = {}
		for _, t in ipairs(tags) do
			if t:lower():find(q, 1, true) then
				filtered[#filtered + 1] = t
			end
		end
		tags = filtered
	end

	if #tags == 0 then
		vim.notify("No tags", vim.log.levels.INFO)
		return
	end

	--- After a tag is chosen: search for that tag and show the same match picker as note search.
	local function on_tag_chosen(tag)
		run_search_and_pick(cfg.obsidian_vault_dir, { query = tag }, {
			prompt_title = "Obsidian search — " .. tag,
			results_title = "Notes with tag",
			empty_message = "No notes match " .. tag,
		})
	end

	local ok, err = pcall(pick_tags_with_telescope, tags, on_tag_chosen)
	if not ok then
		log.append("pick_tags_with_telescope failed: " .. tostring(err) .. "\n")
		vim.notify("Telescope picker failed (" .. tostring(err) .. "). Using vim.ui.select.", vim.log.levels.WARN)
		pick_tags_ui_select(tags, on_tag_chosen)
	end
end

return search
