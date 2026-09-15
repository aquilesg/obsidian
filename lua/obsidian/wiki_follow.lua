--- Normal mode: follow `[[wiki]]` links to vault notes (`:edit` target file).
---
--- Enabled via `require("obsidian").setup({ wiki_follow = true })` (see `init.lua`).
---
--- @module 'obsidian.wiki_follow'

local util = require("obsidian.util")

--- @param line string
--- @param col_byte integer # 0-based column
--- @return string|nil # inner text of [[...]] (may contain `|alias`)
local function wiki_inner_at_cursor(line, col_byte)
	local pos = col_byte + 1
	local s = 1
	while true do
		local open = line:find("%[%[", s, false)
		if not open then
			return nil
		end
		local close = line:find("%]%]", open + 2, false)
		if not close then
			return nil
		end
		if pos >= open and pos <= close + 1 then
			return line:sub(open + 2, close - 1)
		end
		s = close + 2
	end
end

--- @param vault string
--- @param raw_inner string
--- @return string|nil|"multi"
local function resolve_wiki_to_abs(vault, raw_inner)
	if not raw_inner or raw_inner == "" then
		return nil
	end
	local target = vim.trim(raw_inner)
	local pipe = target:find("|", 1, true)
	if pipe then
		target = vim.trim(target:sub(1, pipe - 1))
	end
	if target == "" then
		return nil
	end
	if target:lower():sub(-3) == ".md" then
		target = target:sub(1, -4)
	end
	target = target:gsub("\\", "/")
	local vault_e = vim.fs.normalize(vim.fn.expand(vault))
	local candidate = vim.fs.normalize(vim.fs.joinpath(vault_e, target .. ".md"))
	local stat = vim.uv.fs_stat(candidate)
	if stat and stat.type == "file" then
		return candidate
	end
	if not target:find("/", 1, true) then
		local globpat = "**/" .. target .. ".md"
		local found = vim.fn.globpath(vault_e, globpat, false, true)
		if type(found) == "string" then
			found = found ~= "" and { found } or {}
		end
		if #found == 1 then
			return vim.fs.normalize(found[1])
		elseif #found > 1 then
			table.sort(found)
			vim.ui.select(found, { prompt = "Multiple notes match — pick one:" }, function(choice)
				if choice then
					vim.cmd("edit " .. vim.fn.fnameescape(choice))
				end
			end)
			return "multi"
		end
	end
	-- Fallback: no file is named `target`, so treat it as an Obsidian alias and look
	-- for a note whose frontmatter `aliases` list contains it (e.g. `[[Some Alias]]`).
	local search = require("obsidian.search")
	local alias_matches = search.FindNotesMatchingProperty("aliases", target)
	if alias_matches and #alias_matches > 0 then
		if #alias_matches == 1 then
			return vim.fs.normalize(vim.fs.joinpath(vault_e, alias_matches[1]))
		end
		local abs_matches = {}
		for _, rel in ipairs(alias_matches) do
			abs_matches[#abs_matches + 1] = vim.fs.normalize(vim.fs.joinpath(vault_e, rel))
		end
		table.sort(abs_matches)
		vim.ui.select(abs_matches, { prompt = "Multiple notes match alias — pick one:" }, function(choice)
			if choice then
				vim.cmd("edit " .. vim.fn.fnameescape(choice))
			end
		end)
		return "multi"
	end
	return nil
end

--- @return boolean # true if the key was handled (caller should not fall through)
local function follow_wiki_link()
	local buf = vim.api.nvim_get_current_buf()
	local vault = require("obsidian").get_vault_dir()
	if not vault then
		return false
	end
	if not util.isBufferInVault(buf) then
		return false
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row, col = cursor[1], cursor[2]
	local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
	local inner = wiki_inner_at_cursor(line, col)
	if not inner then
		return false
	end
	local abs = resolve_wiki_to_abs(vault, inner)
	if abs == "multi" then
		return true
	end
	if not abs then
		vim.notify("Could not resolve wiki link: " .. inner, vim.log.levels.WARN)
		return true
	end
	vim.cmd("edit " .. vim.fn.fnameescape(abs))
	return true
end

--- @class obsidian.wiki_follow.SetupOpts
--- @field enabled boolean
--- @field key string # default "<CR>"
--- @field filetypes string[] # default { "markdown" }
--- @field augroup_name string # default "ObsidianWikiFollow"

local M = {}

--- @param opts obsidian.wiki_follow.SetupOpts
function M.setup(opts)
	if not opts or not opts.enabled then
		return
	end
	local key = opts.key or "<CR>"
	local fts = opts.filetypes or { "markdown" }
	local augroup = opts.augroup_name or "ObsidianWikiFollow"

	local function try_map(buf)
		if vim.b[buf].obsidian_wiki_follow_mapped then
			return
		end
		if not util.isBufferInVault(buf) then
			return
		end
		if not vim.tbl_contains(fts, vim.bo[buf].filetype) then
			return
		end
		vim.b[buf].obsidian_wiki_follow_mapped = true
		vim.keymap.set("n", key, function()
			if follow_wiki_link() then
				return
			end
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "n", false)
		end, { buffer = buf, desc = "Follow [[wiki]] link (or default key)" })
	end

	vim.api.nvim_create_augroup(augroup, { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = fts,
		callback = function(ev)
			local buf = ev.buf
			try_map(buf)
			vim.schedule(function()
				try_map(buf)
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,
		callback = function(ev)
			if not vim.tbl_contains(fts, vim.bo[ev.buf].filetype) then
				return
			end
			try_map(ev.buf)
		end,
	})
end

M.follow_wiki_link = follow_wiki_link

return M
