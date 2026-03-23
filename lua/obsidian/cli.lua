local Obsidian = {}

local log = require("obsidian.log")

--- Run `obsidian …` with stdout+stderr written to a temp file, then read it back.
--- `vim.fn.system()` can return an empty string for very large output even when exit code is 0;
--- redirecting to a file avoids that limit.
---@param cmd string Arguments after the obsidian executable (e.g. `search:context format=json query=…`)
---@return string captured output (may be empty)
---@return integer shell exit code (vim.v.shell_error semantics)
---@return string full shell line used (redirect to temp file; for debug logs)
local function systemObsidianToTempfile(cmd)
	local cfg = require("obsidian").getConfig()
	local tmp = vim.fn.tempname() .. ".obsidian-nvim.out"
	local obsidianCmd = vim.fn.shellescape(cfg.obsidian_cli) .. " " .. cmd
	local shell_cmd = obsidianCmd .. " > " .. vim.fn.shellescape(tmp) .. " 2>&1"
	vim.fn.system(shell_cmd)
	local exit_code = vim.v.shell_error
	local content = ""
	if vim.fn.filereadable(tmp) == 1 then
		local lines = vim.fn.readfile(tmp)
		content = table.concat(lines, "\n")
	end
	pcall(vim.fn.delete, tmp)
	return content, exit_code, shell_cmd
end

---@param s string
---@return string
local function normalizeCliOutput(s)
	s = vim.trim(s)
	-- UTF-8 BOM
	if s:sub(1, 3) == "\239\187\191" then
		s = s:sub(4)
	end
	return s
end

---@param s string
---@return any|nil, string|nil error message if decode failed
local function decodeJsonString(s)
	if s == "" then
		return nil, "empty output after trim (nothing to decode)"
	end
	local ok, res = pcall(vim.fn.json_decode, s)
	if ok then
		return res
	end
	local err1 = tostring(res)
	if vim.json and vim.json.decode then
		ok, res = pcall(vim.json.decode, s)
		if ok then
			return res
		end
	end
	return nil, err1
end

--- Run a shell command and return its output.
-- @param cmd string: The shell command to run.
-- @return string|nil: The command output, or nil on error.
function Obsidian.runCommand(cmd)
	local cfg = require("obsidian").getConfig()
	local obsidianCmd = vim.fn.shellescape(cfg.obsidian_cli) .. " " .. cmd
	local output = vim.fn.system(obsidianCmd)
	if vim.v.shell_error ~= 0 then
		vim.notify("Command failed: " .. obsidianCmd, vim.log.levels.ERROR)
		log.capture(string.format("runCommand FAILED\nexit_code=%d\ncmd=%s", vim.v.shell_error, obsidianCmd), output)
		return nil
	end
	return output
end

--- Run a shell command and return trimmed text output (stdout and stderr merged; no JSON).
--- @param cmd string
--- @return string|nil
function Obsidian.runTextCommand(cmd)
	local cfg = require("obsidian").getConfig()
	local obsidianCmd = vim.fn.shellescape(cfg.obsidian_cli) .. " " .. cmd
	local output, exit_code, shell_cmd = systemObsidianToTempfile(cmd)

	log.capture(
		string.format("runTextCommand capture\nexit_code=%d\ncmd=%s\nshell_cmd=%s", exit_code, obsidianCmd, shell_cmd),
		output
	)

	if exit_code ~= 0 then
		local msg = "Command failed: " .. obsidianCmd .. " — details: " .. log.path
		if exit_code == 127 then
			msg = msg
				.. " — set obsidian_cli to the full path to the binary (GUI Neovim often lacks your shell PATH)."
		end
		vim.notify(msg, vim.log.levels.ERROR)
		return nil
	end

	return normalizeCliOutput(output)
end

--- Run a shell command and parse its JSON output.
-- stderr is merged into stdout (2>&1) so JSON emitted only on stderr is still parsed.
-- @param cmd string: The shell command to run.
-- @return table|nil: The parsed JSON table, or nil on error.
function Obsidian.runJsonCommand(cmd)
	local cfg = require("obsidian").getConfig()
	local obsidianCmd = vim.fn.shellescape(cfg.obsidian_cli) .. " " .. cmd
	local output, exit_code, shell_cmd = systemObsidianToTempfile(cmd)

	log.capture(
		string.format("runJsonCommand capture\nexit_code=%d\ncmd=%s\nshell_cmd=%s", exit_code, obsidianCmd, shell_cmd),
		output
	)

	if exit_code ~= 0 then
		local msg = "Command failed: " .. obsidianCmd .. " — details: " .. log.path
		if exit_code == 127 then
			msg = msg
				.. " — set obsidian_cli to the full path to the binary (GUI Neovim often lacks your shell PATH)."
		end
		vim.notify(msg, vim.log.levels.ERROR)
		return nil
	end

	local normalized = normalizeCliOutput(output)
	local parsed, decode_err = decodeJsonString(normalized)

	if parsed ~= nil then
		return parsed
	end

	log.append(
		string.format(
			"runJsonCommand JSON decode FAILED (raw output was logged above in capture)\ncmd=%s\ndecode_error=%s\n",
			obsidianCmd,
			decode_err or "?"
		)
	)
	vim.notify(
		"Failed to parse JSON from obsidian CLI: " .. (decode_err or "unknown") .. " — see " .. log.path,
		vim.log.levels.ERROR
	)
	return nil
end

return Obsidian
