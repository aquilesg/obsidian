--- Telescope picker: notes that match a tag (default `active`), with optional template-dir skip.
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
---@field vault? string # defaults to `obsidian.getConfig().obsidian_vault_dir`
---@field template_dir_name? string # skip notes whose path contains this (default `"Templates"`)
---@field tag? string # tag passed to `FindByTags` (default `"active"`)
---@field property_keys? { status?: string, document_type?: string, id?: string } # YAML keys for preview columns

--- Open a Telescope finder for notes that have `opts.tag`, showing id / document_type / status.
function M.open_picker(opts)
	opts = opts or {}
	local ok, _ = pcall(require, "telescope.pickers")
	if not ok then
		vim.notify("obsidian.active_notes: install telescope.nvim to use this picker", vim.log.levels.WARN)
		return
	end

	local cfg = require("obsidian").getConfig()
	local vault = opts.vault or cfg.obsidian_vault_dir
	if not vault then
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
		return
	end
	vault = vim.fn.expand(vault)

	local template_dir = opts.template_dir_name or "Templates"
	local tag = opts.tag or "active"
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

	local active_notes = search.FindByTags({ tag })
	if not active_notes or vim.tbl_isempty(active_notes) then
		vim.notify("No notes found for tag: " .. tag, vim.log.levels.INFO)
		return
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
			prompt_title = "Active notes (" .. tag .. ")",
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
