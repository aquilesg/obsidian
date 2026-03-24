local search = {}

local log = require("obsidian.log")

---@class NoteSearchOpts
---@field query string # Text to search for
---@field folder string | nil # Folder within vault to limit search to

local util = require("obsidian.util")

--- `tag name="..."` must not include a leading `#`. Trim and strip one leading `#` if present.
---@param tag string
---@return string
local function tag_query_value(tag)
	tag = vim.trim(tag or "")
	if tag:sub(1, 1) == "#" then
		return tag:sub(2)
	end
	return tag
end

---@param scope string
---@param label string
---@param paths string[]
local function log_tag_path_set(scope, label, paths)
	table.sort(paths)
	local max_lines = 80
	local n = #paths
	local body
	if n == 0 then
		body = "(empty)\n"
	elseif n <= max_lines then
		body = table.concat(paths, "\n") .. "\n"
	else
		local chunk = {}
		for i = 1, max_lines do
			chunk[#chunk + 1] = paths[i]
		end
		body = table.concat(chunk, "\n")
			.. "\n... ["
			.. (n - max_lines)
			.. " more paths omitted; total "
			.. n
			.. "]\n"
	end
	log.append(scope .. ": " .. label .. " — " .. n .. " path(s)\n" .. body)
end

---@class NoteMatchPickerOpts
---@field prompt_title string|nil
---@field results_title string|nil
---@field empty_message string|nil  Shown when the search returns no matches (default: "No matches")

--- Presents a Telescope picker for a list of files.
---@param vault_dir string
---@param files string[]
local function pick_files_with_telescope(vault_dir, files)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = "Notes with tag",
			results_title = "Files",
			finder = finders.new_table({
				results = files,
				entry_maker = function(file)
					local abs_path = vim.fs.joinpath(vault_dir, file)
					return {
						value = file,
						display = file,
						ordinal = file,
						path = abs_path, -- Needed for previewer
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.file_previewer({}), -- Add this line
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection and selection.value then
						local path = vim.fs.joinpath(vault_dir, selection.value)
						vim.cmd("edit " .. vim.fn.fnameescape(path))
					end
				end)
				return true
			end,
		})
		:find()
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

--- Populate the tag list from `obsidian tags`, pick a tag in Telescope, then run
--- `tag name="<tag>"` and show a picker of files.
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

	local function on_tag_chosen(tag)
		local vault_dir = cfg.obsidian_vault_dir
		local cmd = 'tag name="' .. util.escapeObsidianCliDoubleQuoted(tag_query_value(tag)) .. '"'
		local files = require("obsidian.cli").runTextCommand(cmd)
		if not files or files == "" then
			vim.notify("No notes match " .. tag, vim.log.levels.INFO)
			return
		end
		local file_list = vim.split(vim.trim(files), "\n", { plain = true })
		pick_files_with_telescope(vault_dir, file_list)
	end

	local ok, err = pcall(pick_tags_with_telescope, tags, on_tag_chosen)
	if not ok then
		log.append("pick_tags_with_telescope failed: " .. tostring(err) .. "\n")
		vim.notify("Telescope picker failed (" .. tostring(err) .. "). Using vim.ui.select.", vim.log.levels.WARN)
		pick_tags_ui_select(tags, on_tag_chosen)
	end
end

--- FindBacklinks of the currently active note
---@param note_path ?string # Path relative to the vault to look for
function search.FindBacklinks(note_path)
	local target = note_path
	local cfg = require("obsidian").getConfig()
	if not cfg.obsidian_vault_dir then
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
		return
	end

	if not note_path then
		target = require("obsidian.util").get_relative_path(vim.api.nvim_buf_get_name(0), cfg.obsidian_vault_dir)
	end

	local backlinks = require("obsidian.cli").runJsonCommand(string.format('backlinks path="%s" format=json', target))
	local files = {}
	if type(backlinks) ~= "table" then
		vim.notify("No backlinks found", vim.log.levels.ERROR)
		return
	end
	for _, item in ipairs(backlinks) do
		if item.file then
			table.insert(files, item.file)
		end
	end

	pick_files_with_telescope(cfg.obsidian_vault_dir, files)
end

--- Finds all notes that match all the passed in tags
---@param tagList string[] Tags to search for
---@return string[]|nil # The path of the note, relative to the vault.
function search.FindByTags(tagList)
	local cfg = require("obsidian").getConfig()
	if not cfg.obsidian_vault_dir then
		log.append("FindByTags: obsidian_vault_dir not configured\n")
		return
	end

	if not tagList or #tagList == 0 then
		log.append("No tags provided\n")
		return
	end

	local sets = {}
	local tags_used = {}
	for _, tag in ipairs(tagList) do
		tag = tag_query_value(tag)
		if tag == "" then
			log.append("FindByTags: empty tag in list\n")
			return
		end
		local cmd = 'tag name="' .. util.escapeObsidianCliDoubleQuoted(tag) .. '"'
		local files = require("obsidian.cli").runTextCommand(cmd)
		if not files or files == "" then
			log.append("No notes match tag: " .. tag .. "\n")
			return
		end
		local file_list = vim.split(vim.trim(files), "\n", { plain = true })
		local set = {}
		for _, f in ipairs(file_list) do
			if f ~= "" then
				set[f] = true
			end
		end
		table.insert(sets, set)
		table.insert(tags_used, tag)
	end

	if #sets == 0 then
		log.append("FindByTags: no tag sets produced\n")
		return
	end

	-- Start from first tag’s files, then intersect one tag at a time (with logging).
	local working = {}
	for path in pairs(sets[1]) do
		working[#working + 1] = path
	end
	log_tag_path_set("FindByTags", "after tag " .. tags_used[1] .. " (initial)", working)

	for i = 2, #sets do
		local next_list = {}
		local set_i = sets[i]
		for _, path in ipairs(working) do
			if set_i[path] then
				next_list[#next_list + 1] = path
			end
		end
		log_tag_path_set(
			"FindByTags",
			"after intersecting with " .. tags_used[i] .. " (was " .. #working .. ", now " .. #next_list .. ")",
			next_list
		)
		working = next_list
	end

	if #working == 0 then
		log.append("FindByTags: no notes match all tags (intersection empty)\n")
		return
	end

	return working
end

--- Finds all notes that match **any** of the passed-in tags (set union).
--- Tags with no matching notes are skipped; logging shows the union growing after each tag.
---@param tagList string[] Tags to search for
---@return string[]|nil # Paths relative to the vault, or nil if none.
function search.FindByTagsUnion(tagList)
	local cfg = require("obsidian").getConfig()
	if not cfg.obsidian_vault_dir then
		log.append("FindByTagsUnion: obsidian_vault_dir not configured\n")
		return
	end

	if not tagList or #tagList == 0 then
		log.append("FindByTagsUnion: no tags provided\n")
		return
	end

	local union = {}
	local union_count = function()
		local n = 0
		for _ in pairs(union) do
			n = n + 1
		end
		return n
	end
	local union_to_list = function()
		local list = {}
		for path in pairs(union) do
			list[#list + 1] = path
		end
		return list
	end

	for _, tag in ipairs(tagList) do
		tag = tag_query_value(tag)
		if tag == "" then
			log.append("FindByTagsUnion: empty tag in list, skipping\n")
		else
			local cmd = 'tag name="' .. util.escapeObsidianCliDoubleQuoted(tag) .. '"'
			local files = require("obsidian.cli").runTextCommand(cmd)
			if not files or files == "" then
				log.append("FindByTagsUnion: no notes for tag " .. tag .. ", skipping\n")
			else
				local before = union_count()
				local file_list = vim.split(vim.trim(files), "\n", { plain = true })
				for _, f in ipairs(file_list) do
					if f ~= "" then
						union[f] = true
					end
				end
				local after = union_count()
				log_tag_path_set(
					"FindByTagsUnion",
					"after adding "
						.. tag
						.. " (unique paths was "
						.. before
						.. ", now "
						.. after
						.. "; +"
						.. (after - before)
						.. ")",
					union_to_list()
				)
			end
		end
	end

	local result = union_to_list()
	if #result == 0 then
		log.append("FindByTagsUnion: no notes match any of the tags (union empty)\n")
		return
	end

	return result
end

return search
