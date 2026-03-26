--- Telescope picker: notes that match a tag (default `active`) **or** a YAML property value, with optional template-dir skip.
---
--- Requires **telescope.nvim**. Call `open_picker` from a keymap.
---
--- @module 'obsidian.active_notes'

local M = {}

---@param val any
---@return string
local function to_str(val)
	if type(val) == "table" then
		return vim.inspect(val)
	elseif val == nil then
		return "N/A"
	else
		return tostring(val)
	end
end

---@class obsidian.active_notes.PickerOpts
---@field vault? string # defaults to `obsidian.get_vault_dir()` / `ensure_vault_dir()`
---@field template_dir_name? string # skip notes whose path contains this (default `"Templates"`)
---@field tag? string # used with `FindByTags` when `active_property` is nil (default `"active"`)
---@field active_property? { key: string, value: string|number } # if set, notes where frontmatter `key` equals `value` (list values: membership); ignores `tag`
---@field property_keys? { status?: string, document_type?: string, id?: string } # YAML keys for preview columns

--- Open a Telescope finder for notes that match `opts.tag` or `opts.active_property`, showing id / document_type / status.
function M.open_picker(opts)
	opts = opts or {}
	local ok, _ = pcall(require, "telescope.pickers")
	if not ok then
		vim.notify("obsidian.active_notes: install telescope.nvim to use this picker", vim.log.levels.WARN)
		return
	end

	local obsidian = require("obsidian")
	local vault = opts.vault and vim.fs.normalize(vim.fn.expand(opts.vault)) or obsidian.ensure_vault_dir()
	if not vault then
		return
	end

	local template_dir = opts.template_dir_name or "Templates"
	local tag = opts.tag or "active"
	local ap = opts.active_property
	local pk = opts.property_keys or {}
	local status_k = pk.status or "status"
	local doc_k = pk.document_type or "document_type"
	local id_k = pk.id or "id"

	local search = require("obsidian.search")
	local noteAPI = require("obsidian.note")
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local conf = require("telescope.config").values

	local active_notes ---@type string[]|nil
	local filter_label ---@type string
	if ap and ap.key and ap.key ~= "" then
		active_notes = search.FindNotesMatchingProperty(ap.key, ap.value)
		filter_label = ap.key .. "=" .. tostring(ap.value)
		if not active_notes or vim.tbl_isempty(active_notes) then
			vim.notify("No notes found for property: " .. filter_label, vim.log.levels.INFO)
			return
		end
	else
		active_notes = search.FindByTags({ tag })
		filter_label = "#" .. tag
		if not active_notes or vim.tbl_isempty(active_notes) then
			vim.notify("No notes found for tag: " .. tag, vim.log.levels.INFO)
			return
		end
	end

	local display_notes = {}
	for _, note_path in ipairs(active_notes) do
		if not string.find(note_path, template_dir, 1, true) then
			local properties = noteAPI.GetNoteProperties(note_path, {
				status_k,
				doc_k,
				id_k,
			})

			local id = to_str(properties[id_k])
			local doc_type = to_str(properties[doc_k])
			local status = to_str(properties[status_k])

			display_notes[#display_notes + 1] = {
				display = string.format("%s -> %s -> %s", id, doc_type, status),
				ordinal = id .. " " .. doc_type .. " " .. status,
				path = vim.fs.joinpath(vault, note_path),
			}
		end
	end

	if #display_notes == 0 then
		vim.notify("No notes to show (after template filter)", vim.log.levels.INFO)
		return
	end

	pickers
		.new({}, {
			prompt_title = "Active notes (" .. filter_label .. ")",
			finder = finders.new_table({
				results = display_notes,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.ordinal,
						path = entry.path,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection and selection.path then
						vim.cmd("edit " .. vim.fn.fnameescape(selection.path))
					end
				end)
				return true
			end,
		})
		:find()
end

return M
