local M = {}

local config = {
	-- Location of the vault within the filesystem
	obsidian_vault_dir = nil,
	-- directory that contains templates
	template_dir = nil,
}

function M.setup(opts)
	opts = opts or {}
	config.obsidian_vault_dir = opts.obsidian_vault_dir and vim.fn.expand(opts.obsidian_vault_dir) or nil
end

function M.get_config()
	return config
end

return M
