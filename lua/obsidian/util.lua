local M = {}

--- Check for input file existence
---@param path string # Path to check
---@return boolean # Indicator if file exists
function M.check_file_exists(path)
	local stat = vim.uv.fs_stat(path)
	return stat and stat.type == "file"
end

--- Copies a file over and renames it
---@param path string # Path of file to copy
---@param destination string # Destination directory to put file
---@param newTitle string # New filename for the copied file
---@return nil|string # nil on success, error message on failure
function M.copy_file_and_rename(path, destination, newTitle)
	-- Ensure destination ends with a slash
	if string.sub(destination, -1) ~= "/" then
		destination = destination .. "/"
	end
	local newPath = destination .. newTitle

	local infile = io.open(path, "rb")
	if not infile then
		return "Failed to open source file: " .. path
	end

	local content = infile:read("*a")
	infile:close()

	local outfile = io.open(newPath, "wb")
	if not outfile then
		return "Failed to create destination file: " .. newPath
	end

	outfile:write(content)
	outfile:close()
	return nil
end

--- Find and replace template variables in a file.
---@param path string # Path to the file
---@param vars table<string, string> # Table of variables to replace
---@return nil|string # nil on success, error message on failure
function M.find_and_replace(path, vars)
	local infile = io.open(path, "r")
	if not infile then
		return "Failed to open file for reading: " .. path
	end
	local content = infile:read("*a")
	infile:close()

	for key, value in pairs(vars or {}) do
		-- Replace all instances of {{ key }} with value
		content = content:gsub("{{%s*" .. key .. "%s*}}", value)
	end

	local outfile = io.open(path, "w")
	if not outfile then
		return "Failed to open file for writing: " .. path
	end
	outfile:write(content)
	outfile:close()
	return nil
end

return M
