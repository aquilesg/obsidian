local M = {}

local config = {
	-- Location of the vault within the filesystem
	obsidian_vault_dir = nil,
	-- directory that contains templates
	template_dir = nil,
	-- Executable for the Obsidian CLI (name on PATH or absolute path). Neovim's :help system()
	-- does not use an interactive shell, so ~/.zshrc PATH changes often do not apply; set this if
	-- you get "command not found" (exit 127) for `obsidian`.
	obsidian_cli = "obsidian",
}

function M.setup(opts)
	opts = opts or {}
	config.obsidian_vault_dir = opts.obsidian_vault_dir and vim.fn.expand(opts.obsidian_vault_dir) or nil
	config.template_dir = opts.template_dir
	config.obsidian_cli = vim.fn.expand(opts.obsidian_cli or "obsidian")
end

function M.getConfig()
	return config
end

return M
