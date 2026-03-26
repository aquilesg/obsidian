--- Helpers for Obsidian note YAML / CLI properties (encoding, blocked-by, list fields).
---
--- @module 'obsidian.note_properties'

local M = {}

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
	local cfg = require("obsidian").getConfig()
	local vault = cfg.obsidian_vault_dir
	if not vault then
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
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

return M
