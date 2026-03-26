--- Shared blink.cmp tag source: `tags_body` vs `tags_frontmatter` differ only in where they activate.
---
--- @module 'obsidian.cmp.tags_shared'

local obsidian = require("obsidian")
local search = require("obsidian.search")

--- Shown in the blink menu via `kind_icon` (e.g. Nerd Font tag glyph U+F02B).
local TAG_KIND_ICON = ""

--- @class obsidian.cmp.TagsSourceOpts
--- @field filetypes? string[]
--- @field vault_dir? string
--- @field tag_cache_ttl? number

--- True when the cursor lies strictly between the opening `---` on line 1 and the next line that is only `---`.
---@param bufnr integer
---@param cursor_line_1 integer 1-based line number
---@return boolean
local function cursor_in_frontmatter(bufnr, cursor_line_1)
	local n = vim.api.nvim_buf_line_count(bufnr)
	if n < 2 then
		return false
	end
	local first = vim.trim(vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or "")
	if first ~= "---" then
		return false
	end
	local close_line ---@type integer|nil
	for i = 2, n do
		local line = vim.trim(vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or "")
		if line == "---" then
			close_line = i
			break
		end
	end
	if not close_line then
		return false
	end
	return cursor_line_1 > 1 and cursor_line_1 < close_line
end

---@param mode "body"|"frontmatter"
---@param bufnr integer
---@param cursor_line_1 integer
---@return boolean
local function cursor_matches_mode(mode, bufnr, cursor_line_1)
	local in_fm = cursor_in_frontmatter(bufnr, cursor_line_1)
	if mode == "frontmatter" then
		return in_fm
	end
	return not in_fm
end

---@param line string
---@param col0 number
---@return integer|nil
local function find_tag_hash_start(line, col0)
	if col0 < 1 then
		return nil
	end
	for i = col0, 1, -1 do
		if line:sub(i, i) == "#" then
			local after = line:sub(i + 1, col0)
			if not after:find("%s") and (after == "" or after:sub(1, 1) ~= " ") then
				return i
			end
		end
	end
	return nil
end

---@param line string
---@param col0 number
---@param line_nr integer
---@return table|nil
local function tag_replace_range(line, col0, line_nr)
	local hash_1 = find_tag_hash_start(line, col0)
	if not hash_1 then
		return nil
	end
	return {
		start = { line = line_nr - 1, character = hash_1 - 1 },
		["end"] = { line = line_nr - 1, character = col0 },
	}
end

--- YAML-ish lines where tag names without `#` make sense (list items, optional `tags:` inline).
---@param line string
---@return boolean
local function frontmatter_line_allows_bare_tag_completion(line)
	if line:match("^%s*-%s") then
		return true
	end
	if line:match("^%s*tags:%s") then
		return true
	end
	return false
end

--- Replace range for bare YAML tags: from first char after `^%s*-%s+` or `^%s*tags:%s*` through the cursor.
--- Using blink `ctx.bounds` here often mis-sized the span (e.g. length 0), which inserted `foo/bar` after `fo` → `fofoo/bar`.
---@param line string
---@param col0 number 0-indexed cursor column (end of replacement, exclusive)
---@param line_nr integer 1-based line number
---@return table|nil
local function bare_tag_replace_range(line, col0, line_nr)
	local _, match_end = line:find("^%s*-%s+")
	if not match_end then
		_, match_end = line:find("^%s*tags:%s*")
	end
	if not match_end then
		return nil
	end
	--- 0-indexed column where the tag fragment starts (first byte after list / `tags:` prefix).
	local tag_start_0 = match_end
	if col0 <= tag_start_0 then
		return nil
	end
	return {
		start = { line = line_nr - 1, character = tag_start_0 },
		["end"] = { line = line_nr - 1, character = col0 },
	}
end

---@param tag_line string
---@return string
local function tag_filter_text(tag_line)
	tag_line = vim.trim(tag_line)
	if tag_line:sub(1, 1) == "#" then
		return tag_line:sub(2)
	end
	return tag_line
end

--- @class obsidian.cmp.TagsSourceInstance
--- @field _mode "body"|"frontmatter"
--- @field opts obsidian.cmp.TagsSourceOpts
--- @field filetypes string[]

--- Shared tag list cache so `tags_body` + `tags_frontmatter` do not each shell out separately.
local tag_list_cache = { tags = nil, at = 0 }

local M = {}

--- @param mode "body"|"frontmatter"
--- @param opts obsidian.cmp.TagsSourceOpts
--- @param _provider? table
--- @return obsidian.cmp.TagsSourceInstance
function M.new(mode, opts, _provider)
	opts = opts or {}
	--- @type obsidian.cmp.TagsSourceInstance
	local self = setmetatable({}, { __index = M })
	self._mode = mode
	self.opts = opts
	self.filetypes = opts.filetypes or { "markdown" }
	return self
end

--- @param self obsidian.cmp.TagsSourceInstance
function M:enabled()
	if not vim.tbl_contains(self.filetypes, vim.bo.filetype) then
		return false
	end
	local buf = vim.api.nvim_get_current_buf()
	local line_1 = vim.api.nvim_win_get_cursor(0)[1]
	return cursor_matches_mode(self._mode, buf, line_1)
end

function M:get_trigger_characters()
	if self._mode == "frontmatter" then
		-- `#` Obsidian-style; `-` / `:` help YAML `tags:` and list lines without typing `#`.
		return { "#", "-", ":" }
	end
	return { "#" }
end

--- @param self obsidian.cmp.TagsSourceInstance
function M:_vaultDir()
	if self.opts.vault_dir then
		return vim.fs.normalize(vim.fn.expand(self.opts.vault_dir))
	end
	return obsidian.get_vault_dir()
end

--- @param self obsidian.cmp.TagsSourceInstance
function M:_getTagsCached()
	local ttl = self.opts.tag_cache_ttl
	if ttl == nil then
		ttl = 30
	end
	local now = os.time()
	if tag_list_cache.tags and (now - tag_list_cache.at) < ttl then
		return tag_list_cache.tags
	end
	local tags = search.getTags()
	if not tags then
		return nil
	end
	tag_list_cache.tags = tags
	tag_list_cache.at = now
	return tags
end

--- @param self obsidian.cmp.TagsSourceInstance
--- @param ctx blink.cmp.Context
--- @param callback fun(response: table)
function M:get_completions(ctx, callback)
	local cancel = function() end

	if not self:_vaultDir() then
		callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
		return cancel
	end

	if not cursor_matches_mode(self._mode, ctx.bufnr, ctx.cursor[1]) then
		callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
		return cancel
	end

	local line = ctx.line
	local col0 = ctx.cursor[2]
	local line_nr = ctx.cursor[1]

	--- Hash-based `#tag` (body + frontmatter); or frontmatter-only bare tags on `-` / `tags:` lines.
	local range = tag_replace_range(line, col0, line_nr)
	local bare_yaml_tags = false
	if not range and self._mode == "frontmatter" and frontmatter_line_allows_bare_tag_completion(line) then
		range = bare_tag_replace_range(line, col0, line_nr)
		bare_yaml_tags = range ~= nil
	end
	if not range then
		callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
		return cancel
	end

	local tags = self:_getTagsCached()
	if not tags then
		callback({ items = {}, is_incomplete_backward = false, is_incomplete_forward = false })
		return cancel
	end

	local kinds = require("blink.cmp.types").CompletionItemKind
	local plain = vim.lsp.protocol.InsertTextFormat.PlainText

	--- @type table[]
	local items = {}
	for _, tag_line in ipairs(tags) do
		if tag_line ~= "" then
			local insert = bare_yaml_tags and tag_filter_text(tag_line) or tag_line
			local label = bare_yaml_tags and insert or tag_line
			items[#items + 1] = {
				label = label,
				kind = kinds.Keyword,
				kind_icon = TAG_KIND_ICON,
				filterText = tag_filter_text(tag_line),
				insertTextFormat = plain,
				textEdit = {
					newText = insert,
					range = range,
				},
			}
		end
	end

	callback({
		items = items,
		is_incomplete_backward = false,
		is_incomplete_forward = false,
	})

	return cancel
end

return M
