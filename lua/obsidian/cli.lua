local Obsidian = {}

--- Run a shell command and return its output.
-- @param cmd string: The shell command to run.
-- @return string|nil: The command output, or nil on error.
function Obsidian.run_command(cmd)
	local obsidianCmd = "obsidian " .. cmd
	local output = vim.fn.system(obsidianCmd)
	if vim.v.shell_error ~= 0 then
		vim.notify("Command failed: " .. obsidianCmd, vim.log.levels.ERROR)
		return nil
	end
	return output
end

--- Run a shell command and parse its JSON output.
-- @param cmd string: The shell command to run.
-- @return table|nil: The parsed JSON table, or nil on error.
function Obsidian.run_json_command(cmd)
	-- Run the command and capture output
	local output = vim.fn.system(cmd)
	-- Check for command errors
	if vim.v.shell_error ~= 0 then
		vim.notify("Command failed: " .. cmd, vim.log.levels.ERROR)
		return nil
	end
	-- Parse JSON output
	local ok, result = pcall(vim.fn.json_decode, output)
	if not ok then
		vim.notify("Failed to parse JSON output", vim.log.levels.ERROR)
		return nil
	end
	return result
end

---@class ObsidianCreateOpts
---@field name string
---@field path string
---@field template string

--- Creates a note
---@param createOpts ObsidianCreateOpts
---@return boolean success
function Obsidian.createNote(createOpts)
	local createNoteCmd = "create name="
		.. createOpts.name
		.. " path="
		.. createOpts.path
		.. " template="
		.. createOpts.template
	local err = Obsidian.run_command(createNoteCmd)

	return err ~= nil
end

return Obsidian
