local M = {}

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
}

function M.setup(opts)
	opts = opts or {}
	config.obsidian_vault_dir = opts.obsidian_vault_dir and vim.fn.expand(opts.obsidian_vault_dir) or nil
	config.template_dir = opts.template_dir
	config.obsidian_cli = vim.fn.expand(opts.obsidian_cli or "obsidian")
	if opts.task_statuses ~= nil then
		config.task_statuses = opts.task_statuses
	end
end

function M.getConfig()
	return config
end

return M
