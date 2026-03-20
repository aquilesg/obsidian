local Obsidian = {}

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

--- Create a note
function Obsidian.create(createOpts)
	local createNoteCmd = "obsidian create name="
		.. createOpts.name
		.. " path="
		.. createOpts.path
		.. " template="
		.. createOpts.templateName
		.. " open"
end

return Obsidian()
