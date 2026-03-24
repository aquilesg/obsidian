local search = {}

local log = require("obsidian.log")

---@class NoteSearchOpts
---@field query string # Text to search for
---@field folder string | nil # Folder within vault to limit search to

--- Obsidian CLI expects `query="..."` (double quotes around the value). Escape `\` and `"` inside the value only.
---@param s string
---@return string
local function escapeObsidianCliDoubleQuoted(s)
	return (s:gsub("\\", "\\\\"):gsub('"', '\\"'))
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
		local cmd = 'tag name="' .. escapeObsidianCliDoubleQuoted(tag) .. '"'
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

return search
