--- Helpers for Obsidian note YAML / CLI properties (encoding, blocked-by, list fields).
---
--- @module 'obsidian.note_properties'

local M = {}

local obsidian = require("obsidian")

--- Serialize values for `obsidian property:set`: comma-separated string lists vs JSON array of objects.
---@param value any
---@return string
function M.encode_property_value(value)
	if type(value) ~= "table" then
		return tostring(value)
	end
	if #value == 0 then
		return ""
	end
	if type(value[1]) == "table" then
		return vim.fn.json_encode(value)
	end
	return table.concat(value, ",")
end

--- If `response` resolves to a single `.md` note under the vault, return `[[path/no-ext]]`; otherwise the trimmed string.
---@param response string
---@param vault string
---@return string
function M.wiki_link_if_vault_note(response, vault)
	local r = vim.trim(response or "")
	if r == "" then
		return r
	end
	if r:match("^%[%[.+%]%]$") then
		return r
	end
	local util = require("obsidian.util")
	local vault_e = vim.fs.normalize(vim.fn.expand(vault))
	local target = r:gsub("\\", "/")
	if target:lower():sub(-3) == ".md" then
		target = target:sub(1, -4)
	end
	local candidate = vim.fs.normalize(vim.fs.joinpath(vault_e, target .. ".md"))
	local stat = vim.uv.fs_stat(candidate)
	if stat and stat.type == "file" then
		return "[[" .. target .. "]]"
	end
	if not target:find("/", 1, true) then
		local found = vim.fn.globpath(vault_e, "**/" .. target .. ".md", false, true)
		if type(found) == "string" then
			found = found ~= "" and { found } or {}
		end
		if #found == 1 then
			local rel = util.get_relative_path(vim.fs.normalize(found[1]), vault)
			if rel and rel ~= "" then
				local link = vim.fn.fnamemodify(rel, ":r"):gsub("\\", "/")
				return "[[" .. link .. "]]"
			end
		end
	end
	return r
end

--- Normalize `blockedBy`-style data from the CLI (strings, JSON array, `{ uid = ... }` rows).
---@param raw any
---@return { uid: string }[]
function M.normalize_blocked_by_list(raw)
	if raw == nil then
		return {}
	end
	if type(raw) == "string" then
		local ok, decoded = pcall(vim.fn.json_decode, raw)
		if ok and type(decoded) == "table" then
			return M.normalize_blocked_by_list(decoded)
		end
		return { { uid = raw } }
	end
	if type(raw) ~= "table" then
		return {}
	end
	if raw.uid ~= nil then
		return { raw }
	end
	local out = {}
	for _, item in ipairs(raw) do
		if type(item) == "string" then
			out[#out + 1] = { uid = item }
		elseif type(item) == "table" and item.uid ~= nil then
			out[#out + 1] = item
		end
	end
	return out
end

--- Read a list property as a Lua list of strings (tags, `pr_link`, etc.).
---@param note_rel string
---@param key string
---@return string[]
function M.get_string_list_property(note_rel, key)
	local Note = require("obsidian.note")
	local existing = Note.GetNoteProperties(note_rel, { key })
	local list = existing[key] or {}
	if type(list) == "string" then
		list = { list }
	end
	return list
end

--- Build `UpdateNoteProperties` rows for “mark blocked” (`<leader>omb`-style): optional `blockedBy` row with `{ uid = [[…]] }` entries.
---
--- When `response` is empty, only status is set. Otherwise the existing blocked list is loaded, one row is appended, and both status + list are written.
---
---@param note_rel string
---@param response string|nil
---@param opts { blocked_property: string, status_property: string, status_value: string }
---@return table[]|nil # property rows, or nil if vault is not configured
function M.properties_for_mark_blocked(note_rel, response, opts)
	local vault = obsidian.ensure_vault_dir()
	if not vault then
		return nil
	end

	local blocked_key = opts.blocked_property
	local status_key = opts.status_property
	local status_val = opts.status_value

	if not response or response == "" then
		return {
			{ name = status_key, value = status_val, type = "text" },
		}
	end

	local Note = require("obsidian.note")
	local existing = Note.GetNoteProperties(note_rel, { blocked_key })
	local reasons = M.normalize_blocked_by_list(existing[blocked_key])
	table.insert(reasons, {
		uid = M.wiki_link_if_vault_note(response, vault),
	})
	return {
		{ name = status_key, value = status_val, type = "text" },
		{ name = blocked_key, value = reasons, type = "list" },
	}
end

--- Tags list with `exclude_tag` removed (e.g. `active` on mark complete), plus completed date + status.
---
---@param note_rel string
---@param opts { tags_key: string, status_key: string, status_complete: string, exclude_tag?: string, completed_date_property?: string }
---@return table[]
function M.properties_for_mark_complete(note_rel, opts)
	local tags_key = opts.tags_key
	local status_key = opts.status_key
	local status_complete = opts.status_complete
	local exclude_tag = opts.exclude_tag or "active"
	local completed_key = opts.completed_date_property or "completedDate"

	local Note = require("obsidian.note")
	local note_tags = Note.GetNoteProperties(note_rel, { tags_key })
	local tag_list = note_tags[tags_key] or {}
	if type(tag_list) == "string" then
		tag_list = { tag_list }
	end
	local filtered = {}
	for _, t in ipairs(tag_list) do
		if t ~= exclude_tag then
			filtered[#filtered + 1] = t
		end
	end

	return {
		{ name = completed_key, value = os.date("%Y-%m-%d"), type = "date" },
		{ name = status_key, value = status_complete, type = "text" },
		{ name = tags_key, value = filtered, type = "list" },
	}
end

--- Add `active_tag` to tags if missing; set status to in-progress.
---
---@param note_rel string
---@param opts { tags_key: string, status_key: string, status_in_progress: string, active_tag?: string }
---@return table[]
function M.properties_for_mark_in_progress(note_rel, opts)
	local tags_key = opts.tags_key
	local status_key = opts.status_key
	local status_in_progress = opts.status_in_progress
	local active_tag = opts.active_tag or "active"

	local tags_new = vim.list_extend({}, M.get_string_list_property(note_rel, tags_key))
	if not vim.tbl_contains(tags_new, active_tag) then
		table.insert(tags_new, active_tag)
	end
	return {
		{ name = status_key, value = status_in_progress, type = "text" },
		{ name = tags_key, value = tags_new, type = "list" },
	}
end

--- Save the current buffer, run **`note.UpdateNoteProperties`** (Obsidian CLI), then **`:edit!`** so frontmatter refreshes.
--- Resolves the note path with **`util.get_relative_path`** and **`obsidian.setup({ obsidian_vault_dir = ... })`**.
---
---@param properties table[] # rows passed to `note.UpdateNoteProperties`
function M.update_note_properties(properties)
	local vault = obsidian.ensure_vault_dir()
	if not vault then
		return
	end

	vim.api.nvim_buf_call(vim.api.nvim_get_current_buf(), function()
		vim.cmd("write")
	end)

	local abs = vim.api.nvim_buf_get_name(0)
	if abs == nil or abs == "" then
		vim.notify("update_note_properties: buffer has no file path", vim.log.levels.WARN)
		return
	end

	local util = require("obsidian.util")
	local rel = util.get_relative_path(abs, vault)
	local Note = require("obsidian.note")
	Note.UpdateNoteProperties(properties, rel)
	vim.cmd("edit!")
end

return M
