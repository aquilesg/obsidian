local M = {}

local log = require("obsidian.log")

--- Checkbox middle characters for `UpdateNoteTask` status picker (`key` → CLI `status=`).
---@return { key: string, label: string }[]
local function default_task_statuses()
	return {
		{ key = " ", label = "Todo [ ]" },
		{ key = "x", label = "Done [x]" },
		{ key = "-", label = "Cancelled [-]" },
		{ key = ">", label = "In progress [>]" },
		{ key = "!", label = "Important [!]" },
		{ key = "?", label = "Question [?]" },
	}
end

local config = {
	-- Location of the vault within the filesystem
	obsidian_vault_dir = nil,
	-- directory that contains templates
	template_dir = nil,
	-- Executable for the Obsidian CLI (name on PATH or absolute path). Neovim's :help system()
	-- does not use an interactive shell, so ~/.zshrc PATH changes often do not apply; set this if
	-- you get "command not found" (exit 127) for `obsidian`.
	obsidian_cli = "/opt/homebrew/bin/obsidian",
	---@type { key: string, label: string }[]
	task_statuses = default_task_statuses(),
	--- Normal mode `[[wiki]]` follow (see `wiki_follow.lua`). Set via `setup({ wiki_follow = ... })`.
	---@type table|nil
	wiki_follow = nil,
	--- Maps template type keys → vault folder (relative). Used by `obsidian.note_creation`.
	---@type table<string, string>|nil
	directories = nil,
	--- Maps template type keys → template **file** base name (under `template_dir`). Used by `obsidian.note_creation`.
	---@type table<string, string>|nil
	template_names = nil,
	--- Your YAML property names (`tags`, `status`, …). Passed through for helpers / templates; optional.
	---@type table<string, string>|nil
	note_properties = nil,
}

---@param wf boolean|table|nil
---@return table|nil
local function normalize_wiki_follow(wf)
	if wf == nil or wf == false then
		return nil
	end
	if wf == true then
		return { enabled = true, key = "<CR>", filetypes = { "markdown" } }
	end
	local t = vim.tbl_extend("force", {
		enabled = true,
		key = "<CR>",
		filetypes = { "markdown" },
	}, wf)
	if not t.enabled then
		return nil
	end
	return t
end

function M.setup(opts)
	opts = opts or {}
	config.obsidian_vault_dir = opts.obsidian_vault_dir and vim.fn.expand(opts.obsidian_vault_dir) or nil
	config.template_dir = opts.template_dir
	config.obsidian_cli = vim.fn.expand(opts.obsidian_cli or "obsidian")
	if opts.task_statuses ~= nil then
		config.task_statuses = opts.task_statuses
	end
	config.wiki_follow = normalize_wiki_follow(opts.wiki_follow)
	if config.wiki_follow then
		require("obsidian.wiki_follow").setup(config.wiki_follow)
	end
	config.directories = opts.directories
	config.template_names = opts.template_names
	config.note_properties = opts.note_properties
end

function M.getConfig()
	return config
end

--- Normalized absolute vault path, or nil. Does not notify.
---@return string|nil
function M.get_vault_dir()
	local v = config.obsidian_vault_dir
	if not v or v == "" then
		return nil
	end
	return vim.fs.normalize(vim.fn.expand(v))
end

---@class obsidian.EnsureVaultOpts
---@field silent? boolean # if true, do not `vim.notify` (logging via `log_scope` still runs)
---@field log_scope? string # on failure, `log.append(scope .. ": obsidian_vault_dir not configured")`

--- Returns normalized vault path, or nil after optional notify/log.
---@param opts? obsidian.EnsureVaultOpts
---@return string|nil
function M.ensure_vault_dir(opts)
	opts = opts or {}
	local v = M.get_vault_dir()
	if v then
		return v
	end
	if opts.log_scope then
		log.append(opts.log_scope .. ": obsidian_vault_dir not configured\n")
	end
	if not opts.silent then
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
	end
	return nil
end

return M
