-- Test configuration for plenary.nvim
local this_file = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fn.fnamemodify(this_file, ":p:h:h")
vim.opt.runtimepath:prepend(repo_root)

local plenary_path = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
	vim.opt.runtimepath:prepend(plenary_path)
end
