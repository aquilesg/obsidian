local Obsidian = {}

local log = require("obsidian.log")

---@param s string
---@return string
local function normalizeCliOutput(s)
	s = vim.trim(s)
	if s:sub(1, 3) == "\239\187\191" then
		s = s:sub(4)
	end
	return s
end

--- Run a shell command and return its output.
--- @param cmd string Arguments after the obsidian executable.
--- @return string|nil
function Obsidian.runCommand(cmd)
	local cfg = require("obsidian").getConfig()
	local obsidianCmd = vim.fn.shellescape(cfg.obsidian_cli) .. " " .. cmd
	local output = vim.fn.system(obsidianCmd)
	if vim.v.shell_error ~= 0 then
		log.append("Encountered err: " .. output)
		vim.notify("Command failed: " .. obsidianCmd, vim.log.levels.ERROR)
		return nil
	end
	return output
end

--- Run a shell command and return trimmed text (stdout + stderr merged).
--- @param cmd string Arguments after the obsidian executable.
--- @return string|nil
function Obsidian.runTextCommand(cmd)
	local cfg = require("obsidian").getConfig()
	local obsidianCmd = vim.fn.shellescape(cfg.obsidian_cli) .. " " .. cmd .. " 2>&1"
	log.append("Running:" .. obsidianCmd)
	local output = vim.fn.system(obsidianCmd)
	log.append("Output" .. output)
	if vim.v.shell_error ~= 0 then
		log.append("Encountered err: " .. output)
		vim.notify("Command failed: " .. obsidianCmd, vim.log.levels.ERROR)
		return nil
	end
	return normalizeCliOutput(output)
end

--- Run a shell command and parse JSON from stdout (same pattern as cb4763: `system` then `json_decode`).
--- @param cmd string Arguments after the obsidian executable.
--- @return table|nil
function Obsidian.runJsonCommand(cmd)
	local cfg = require("obsidian").getConfig()
	local obsidianCmd = vim.fn.shellescape(cfg.obsidian_cli) .. " " .. cmd
	log.append("Command: " .. obsidianCmd)
	local output = vim.fn.system(obsidianCmd)
	if vim.v.shell_error ~= 0 then
		log.append("No Output Found: " .. output)
		return nil
	end
	local ok, result = pcall(vim.fn.json_decode, output)
	if not ok then
		log.append("No Output Found: " .. result)
		log.append("Failed to parse JSON output")
		return nil
	end
	log.append("output: " .. output)
	return result
end

--- Run a command without blocking and parse JSON from stdout. Args are passed to the executable
--- directly (no shell), so values containing spaces need no quoting.
--- @param args string[] Arguments after the obsidian executable.
--- @param cb fun(result: table|nil, err: string|nil) Called on the main loop.
--- @param silent? boolean Skip logging failures (for background polls).
function Obsidian.runJsonCommandAsync(args, cb, silent)
	local cfg = require("obsidian").getConfig()
	local cmd = { cfg.obsidian_cli }
	vim.list_extend(cmd, args)
	vim.system(cmd, { text = true }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				local err = (res.stderr ~= "" and res.stderr) or res.stdout or "unknown error"
				if not silent then
					log.append("Encountered err: " .. err)
				end
				cb(nil, err)
				return
			end
			local ok, result = pcall(vim.json.decode, res.stdout)
			if not ok or type(result) ~= "table" then
				local err = "could not parse output:\n" .. (res.stdout or "")
				if not silent then
					log.append(err)
				end
				cb(nil, err)
				return
			end
			cb(result, nil)
		end)
	end)
end

return Obsidian
