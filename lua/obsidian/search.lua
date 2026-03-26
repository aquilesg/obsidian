local search = {}

local log = require("obsidian.log")
local obsidian = require("obsidian")

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
		body = table.concat(chunk, "\n") .. "\n... [" .. (n - max_lines) .. " more paths omitted; total " .. n .. "]\n"
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
local function pick_files_with_telescope(vault_dir, files, prompt_title)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = prompt_title,
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

--- Fetch all tags from `obsidian tags` (same lines as Telescope tag picker).
--- Returns nil if the vault is not configured or the CLI failed.
---@return string[]|nil
function search.getTags()
	if not obsidian.get_vault_dir() then
		return nil
	end
	local raw = require("obsidian.cli").runTextCommand("tags")
	if raw == nil then
		return nil
	end
	return parse_tag_lines(raw)
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

	local vault = obsidian.ensure_vault_dir({ log_scope = "findWithinTags" })
	if not vault then
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
		local cmd = 'tag name="' .. util.escapeObsidianCliDoubleQuoted(tag_query_value(tag)) .. '"'
		local files = require("obsidian.cli").runTextCommand(cmd)
		if not files or files == "" then
			vim.notify("No notes match " .. tag, vim.log.levels.INFO)
			return
		end
		local file_list = vim.split(vim.trim(files), "\n", { plain = true })
		pick_files_with_telescope(vault, file_list, "Notes with Tag")
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
	local vault = obsidian.ensure_vault_dir()
	if not vault then
		return
	end

	if not note_path then
		target = require("obsidian.util").get_relative_path(vim.api.nvim_buf_get_name(0), vault)
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

	pick_files_with_telescope(vault, files, "Note Backlinks")
end

--- FindLinks of the currently active note
--- @param note_path ?string # Path relative to the vault
function search.FindLinks(note_path)
	local target = note_path
	local vault = obsidian.ensure_vault_dir()
	if not vault then
		return
	end

	if not note_path then
		target = require("obsidian.util").get_relative_path(vim.api.nvim_buf_get_name(0), vault)
	end

	local links = require("obsidian.cli").runTextCommand(string.format('links path="%s"', target))
	log.append("Found links: " .. vim.inspect(links)) -- Use vim.inspect for tables

	local files = {}

	if type(links) == "string" then
		-- Split string by newlines into a table
		for line in links:gmatch("[^\r\n]+") do
			if line ~= "" then
				table.insert(files, line)
			end
		end
	elseif type(links) == "table" then
		for _, item in ipairs(links) do
			if item.file then
				table.insert(files, item.file)
			end
		end
	else
		vim.notify("No links found", vim.log.levels.ERROR)
		return
	end

	pick_files_with_telescope(vault, files, "Note Links")
end

--- Finds all notes that match all the passed in tags
---@param tagList string[] Tags to search for
---@return string[]|nil # The path of the note, relative to the vault.
function search.FindByTags(tagList)
	if not obsidian.ensure_vault_dir({ silent = true, log_scope = "FindByTags" }) then
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
	if not obsidian.ensure_vault_dir({ silent = true, log_scope = "FindByTagsUnion" }) then
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

---@param raw any # scalar or list from simple YAML parse
---@param expected string|number
---@return boolean
local function property_value_matches(raw, expected)
	if raw == nil then
		return false
	end
	local exp = vim.trim(tostring(expected))
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			local s = vim.trim(tostring(v))
			if s:sub(1, 1) == '"' and s:sub(-1, -1) == '"' then
				s = s:sub(2, -2)
			end
			if s == exp then
				return true
			end
		end
		return false
	end
	local s = vim.trim(tostring(raw))
	if s:sub(1, 1) == '"' and s:sub(-1, -1) == '"' then
		s = s:sub(2, -2)
	end
	return s == exp
end

--- Relative `.md` paths under the vault (excluding `.git`, `.obsidian`, `.trash`).
---@param vault_root string
---@return string[]
local function list_vault_md_paths(vault_root)
	local paths = {}
	local exclude = { [".git"] = true, [".obsidian"] = true, [".trash"] = true }
	local ok_depth = pcall(function()
		for _, _ in vim.fs.dir(vault_root, { depth = math.huge }) do
			break
		end
	end)
	if ok_depth then
		for name, ftype in vim.fs.dir(vault_root, { depth = math.huge }) do
			if ftype == "file" and vim.endswith(name, ".md") then
				local first = name:match("^([^/]+)/") or name:match("^([^/]+)$")
				if not exclude[first] then
					paths[#paths + 1] = name
				end
			end
		end
		return paths
	end
	---@param dir string
	---@param rel_prefix string
	local function walk(dir, rel_prefix)
		local ok, iter = pcall(vim.fs.dir, dir)
		if not ok or not iter then
			return
		end
		for name, ftype in iter do
			if name ~= "." and name ~= ".." then
				local rel = rel_prefix == "" and name or (rel_prefix .. "/" .. name)
				if ftype == "file" and vim.endswith(name, ".md") then
					paths[#paths + 1] = rel
				elseif ftype == "directory" then
					local seg = rel:match("^([^/]+)") or rel
					if not exclude[seg] then
						walk(vim.fs.joinpath(dir, name), rel)
					end
				end
			end
		end
	end
	walk(vault_root, "")
	return paths
end

--- Notes whose frontmatter has `property_key` equal to `expected_value` (scalar or list membership).
--- Uses the same simple YAML subset as `util.parseYamlFrontmatterBlock` (no CLI per file).
---@param property_key string
---@param expected_value string|number
---@return string[]|nil # Paths relative to the vault, or nil if none / vault missing.
function search.FindNotesMatchingProperty(property_key, expected_value)
	local vault = obsidian.ensure_vault_dir({ silent = true, log_scope = "FindNotesMatchingProperty" })
	if not vault then
		return nil
	end
	if not property_key or property_key == "" then
		log.append("FindNotesMatchingProperty: empty property_key\n")
		return nil
	end
	local rel_paths = list_vault_md_paths(vault)
	local matches = {}
	for _, rel in ipairs(rel_paths) do
		local abs = vim.fs.joinpath(vault, rel)
		local fd = io.open(abs, "r")
		if fd then
			local content = fd:read("*a")
			fd:close()
			local yaml_inner = select(1, util.splitNoteContent(content))
			if yaml_inner then
				local data, _, err = util.parseYamlFrontmatterBlock(yaml_inner)
				if not err and data and property_value_matches(data[property_key], expected_value) then
					matches[#matches + 1] = rel
				end
			end
		end
	end

	if #matches == 0 then
		log.append(
			"FindNotesMatchingProperty: no notes with "
				.. property_key
				.. "="
				.. tostring(expected_value)
				.. "\n"
		)
		return nil
	end
	table.sort(matches)
	return matches
end

return search
