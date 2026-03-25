--- Blink.cmp source: wiki-style `[[note]]` completion from markdown files in the vault.
---
--- Trigger: type `[[`, then filter by path or title. Inserts the path **without** `.md`
--- (Obsidian-style).
---
--- ```lua
--- obsidian_wiki_links = {
---   name = 'Obsidian (wiki)',
---   module = 'obsidian.cmp.wiki_links',
---   opts = {},
--- },
--- ```
---
--- @module 'obsidian.cmp.wiki_links'

local obsidian = require("obsidian")

local WIKI_KIND_ICON = "󰈔"

--- @class obsidian.cmp.WikiLinksOpts
--- @field filetypes? string[]
--- @field vault_dir? string
--- @field cache_ttl? number # seconds; default 60
--- @field max_items? number # default 400
--- @field exclude_dir_names? string[] # default { ".git", ".obsidian", ".trash" }

--- @param vault_root string
--- @param exclude table<string, boolean>
--- @return string[]
local function list_vault_md_paths(vault_root, exclude)
	local paths = {}
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

--- Relative path without `.md` for wiki link text.
---@param rel_md string
---@return string
local function link_text_from_rel(rel_md)
	local base = vim.fn.fnamemodify(rel_md, ":r") -- drop .md
	return base
end

---@param line string
---@param col_byte number # 0-based nvim cursor column (exclusive end of text before cursor)
---@param cursor_line_1 integer # 1-based line number (from context)
---@return { range: table, fragment: string }|nil
local function wiki_fragment_range(line, col_byte, cursor_line_1)
	if col_byte < 2 then
		return nil
	end
	local before = line:sub(1, col_byte)
	local best_open ---@type integer|nil
	local i = #before - 1
	while i >= 1 do
		if before:sub(i, i + 1) == "[[" then
			local tail = before:sub(i + 2)
			if not tail:find("]]", 1, true) then
				best_open = i
				break
			end
		end
		i = i - 1
	end
	if not best_open then
		return nil
	end
	local frag_start_1 = best_open + 2
	local fragment = ""
	if frag_start_1 <= #before then
		fragment = before:sub(frag_start_1, #before)
	end
	return {
		fragment = fragment,
		range = {
			start = { line = cursor_line_1 - 1, character = frag_start_1 - 1 },
			["end"] = { line = cursor_line_1 - 1, character = col_byte },
		},
	}
end

local path_cache = { paths = nil, at = 0, vault = nil }

local M = {}

--- @param opts obsidian.cmp.WikiLinksOpts
--- @param _provider? table
--- @return table
function M.new(opts, _provider)
	opts = opts or {}
	local self = setmetatable({}, { __index = M })
	self.opts = opts
	self.filetypes = opts.filetypes or { "markdown" }
	return self
end

function M:enabled()
	if vim.in_fast_event() then
		return false
	end
	return vim.tbl_contains(self.filetypes, vim.bo.filetype)
end

function M:get_trigger_characters()
	return { "[" }
end

--- @param self table
function M:_vault_dir()
	if self.opts.vault_dir then
		return vim.fn.expand(self.opts.vault_dir)
	end
	local cfg = obsidian.getConfig()
	return cfg and cfg.obsidian_vault_dir or nil
end

--- @param self table
--- @return string[]|nil
function M:_list_paths_cached()
	local vault = self:_vault_dir()
	if not vault then
		return nil
	end
	local ttl = self.opts.cache_ttl
	if ttl == nil then
		ttl = 60
	end
	local now = os.time()
	if path_cache.paths and path_cache.vault == vault and (now - path_cache.at) < ttl then
		return path_cache.paths
	end
	local exclude_names = self.opts.exclude_dir_names
		or { ".git", ".obsidian", ".trash" }
	local exclude = {}
	for _, n in ipairs(exclude_names) do
		exclude[n] = true
	end
	local paths = list_vault_md_paths(vault, exclude)
	table.sort(paths)
	path_cache.paths = paths
	path_cache.at = now
	path_cache.vault = vault
	return paths
end

--- @param self table
--- @param ctx blink.cmp.Context
--- @param callback fun(response: table)
function M:get_completions(ctx, callback)
	local cancel = function() end

	local vault = self:_vault_dir()
	if not vault then
		callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
		return cancel
	end

	local col_byte = ctx.cursor[2]
	local parsed = wiki_fragment_range(ctx.line, col_byte, ctx.cursor[1])
	if not parsed then
		callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
		return cancel
	end

	local fragment_l = parsed.fragment:lower()
	local paths = self:_list_paths_cached()
	if not paths then
		callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
		return cancel
	end

	local kinds = require("blink.cmp.types").CompletionItemKind
	local plain = vim.lsp.protocol.InsertTextFormat.PlainText
	local max_items = self.opts.max_items or 400

	--- @type table[]
	local items = {}
	for _, rel_md in ipairs(paths) do
		local link = link_text_from_rel(rel_md)
		local base = vim.fn.fnamemodify(rel_md, ":t:r")
		local match = fragment_l == ""
			or link:lower():find(fragment_l, 1, true)
			or rel_md:lower():find(fragment_l, 1, true)
			or base:lower():find(fragment_l, 1, true)
		if match then
			items[#items + 1] = {
				label = link,
				kind = kinds.File,
				kind_icon = WIKI_KIND_ICON,
				filterText = link .. " " .. rel_md .. " " .. base,
				insertTextFormat = plain,
				labelDetails = { description = rel_md },
				textEdit = {
					newText = link,
					range = parsed.range,
				},
			}
			if #items >= max_items then
				break
			end
		end
	end

	callback({
		items = items,
		is_incomplete_backward = false,
		is_incomplete_forward = false,
	})

	return cancel
end

return {
	new = function(opts, provider)
		return M.new(opts, provider)
	end,
}
