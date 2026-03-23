--- Append-only debug log under Neovim's cache dir (`:echo stdpath('cache')`).
local M = {}

M.path = vim.fn.stdpath("cache") .. "/obsidian.nvim.log"

local MAX_RAW_BYTES = 65536

---@param body string
function M.append(body)
	body = body or ""
	local ts = vim.fn.strftime("%Y-%m-%d %H:%M:%S")
	local lines = vim.split("--- " .. ts .. " ---\n" .. body, "\n", { plain = true })
	pcall(vim.fn.writefile, lines, M.path, "a")
end

--- Append a header block plus raw bytes (truncated when very large).
---@param header string
---@param raw string|nil
function M.capture(header, raw)
	raw = raw or ""
	local n = #raw
	local preview
	if n <= MAX_RAW_BYTES then
		preview = raw
	else
		preview = raw:sub(1, MAX_RAW_BYTES) .. "\n... [truncated, total " .. n .. " bytes]\n"
	end
	M.append(string.format("%s\noutput_bytes=%d\n%s", header, n, preview))
end

return M
