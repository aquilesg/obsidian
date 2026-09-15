local Obsidian = {}

local log = require("obsidian.log")

-- Homebrew's prefix differs per platform (Apple Silicon, Intel, Linuxbrew), so the executable is
-- resolved rather than hardcoded. Probed in order, after `$HOMEBREW_PREFIX` and the prefix implied
-- by `brew` itself; none of this shells out.
local BREW_PREFIXES = {
	"/opt/homebrew",
	"/usr/local",
	"/home/linuxbrew/.linuxbrew",
	"~/.linuxbrew",
}

--- @return string[]
local function brewPrefixes()
	local prefixes = {}
	local env_prefix = vim.env.HOMEBREW_PREFIX
	if env_prefix and env_prefix ~= "" then
		prefixes[#prefixes + 1] = env_prefix
	end
	local brew = vim.fn.exepath("brew")
	if brew ~= "" then
		prefixes[#prefixes + 1] = vim.fs.dirname(vim.fs.dirname(brew))
	end
	vim.list_extend(prefixes, BREW_PREFIXES)
	return prefixes
end

-- Resolution is keyed on the configured value so `setup()` changes take effect without an
-- explicit cache reset.
local resolved = { key = nil, path = nil }

--- Absolute path to the Obsidian CLI. An `obsidian_cli` containing a `/` is taken as given;
--- otherwise the name is looked up on `$PATH` and then under the Homebrew prefix. Falls back to
--- the bare name, so the eventual failure names what was run.
--- @return string
function Obsidian.executable()
	local configured = require("obsidian").getConfig().obsidian_cli
	if resolved.key == configured then
		return resolved.path
	end

	local path
	if configured and configured:find("/", 1, true) then
		path = vim.fn.expand(configured)
	else
		local name = (configured and configured ~= "") and configured or "obsidian"
		path = vim.fn.exepath(name)
		if path == "" then
			for _, prefix in ipairs(brewPrefixes()) do
				local candidate = vim.fn.expand(prefix) .. "/bin/" .. name
				if vim.fn.executable(candidate) == 1 then
					path = candidate
					break
				end
			end
		end
		if path == "" then
			path = name
			log.append("executable: " .. name .. " not found on $PATH or under a Homebrew prefix\n")
			vim.notify(
				"Could not find the Obsidian CLI ('"
					.. name
					.. "'). Set `obsidian_cli` to its path in your setup() call.",
				vim.log.levels.ERROR
			)
		end
	end

	resolved = { key = configured, path = path }
	return path
end

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
	local obsidianCmd = vim.fn.shellescape(Obsidian.executable()) .. " " .. cmd
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
	local obsidianCmd = vim.fn.shellescape(Obsidian.executable()) .. " " .. cmd .. " 2>&1"
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
	local obsidianCmd = vim.fn.shellescape(Obsidian.executable()) .. " " .. cmd
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
	local cmd = { Obsidian.executable() }
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
