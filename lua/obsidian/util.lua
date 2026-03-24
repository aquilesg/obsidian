local M = {}

local log = require("obsidian.log")

--- Checks if tables have an intersection
---@param tbl1 table
---@param tbl2 table
function M.has_intersection(tbl1, tbl2)
	local set = {}
	for _, v in ipairs(tbl1) do
		set[v] = true
	end
	for _, v in ipairs(tbl2) do
		if set[v] then
			return true
		end
	end
	return false
end

--- Obsidian CLI expects `key="..."` (double quotes). Escape `\` and `"` inside the value only.
---@param s string
---@return string
function M.escapeObsidianCliDoubleQuoted(s)
	return (tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

function M.get_relative_path(absolute_path, vault_dir)
	if vault_dir:sub(-1) == "/" then
		vault_dir = vault_dir:sub(1, -2)
	end
	if absolute_path:sub(1, #vault_dir) == vault_dir then
		local rel = absolute_path:sub(#vault_dir + 2) -- +2 to skip the slash
		return rel
	else
		return absolute_path
	end
end

local function ensure_dir_exists(dir)
	local stat = vim.uv.fs_stat(dir)
	if not stat then
		vim.uv.fs_mkdir(dir, 448) -- 448 = 0o700
	end
end

--- Check for input file existence
---@param path string # Path to check
---@return boolean # Indicator if file exists
function M.checkFileExists(path)
	local stat = vim.uv.fs_stat(path)
	return stat ~= nil and stat.type == "file"
end

--- Copies a file over and renames it
---@param path string # Path of file to copy
---@param destination string # Destination directory to put file
---@param newTitle string # New filename for the copied file
---@return nil|string # nil on success, error message on failure
function M.copyFileAndRename(path, destination, newTitle)
	-- Ensure destination ends with a slash
	log.append("trying to copy file" .. path .. " to:" .. destination)
	if string.sub(destination, -1) ~= "/" then
		destination = destination .. "/"
	end
	log.append("Destination is now:" .. destination)

	ensure_dir_exists(destination)
	local newPath = destination .. newTitle
	log.append("NewPath is now:" .. newPath)

	local infile = io.open(path, "rb")
	if not infile then
		local msg = "Failed to open source file: " .. path
		log.append(msg)
		vim.notify(msg, vim.log.levels.ERROR)
		return msg
	end

	local content, read_err = infile:read("*a")
	if not content then
		local msg = "Failed to read source file: " .. (read_err or "")
		log.append(msg)
		vim.notify(msg, vim.log.levels.ERROR)
		infile:close()
		return msg
	end

	local ok, close_err = infile:close()
	if not ok then
		local msg = "Failed to close source file: " .. (close_err or "")
		log.append(msg)
		vim.notify(msg, vim.log.levels.ERROR)
		return msg
	end

	local outfile = io.open(newPath, "wb")
	if not outfile then
		local msg = "Failed to create destination file: " .. newPath
		log.append(msg)
		vim.notify(msg, vim.log.levels.ERROR)
		return msg
	end

	local ok, write_err = outfile:write(content)
	if not ok then
		local msg = "Failed to write to destination file: " .. (write_err or "")
		log.append(msg)
		vim.notify(msg, vim.log.levels.ERROR)
		outfile:close()
		return msg
	end

	local ok, close_err = outfile:close()
	if not ok then
		local msg = "Failed to close destination file: " .. (close_err or "")
		log.append(msg)
		vim.notify(msg, vim.log.levels.ERROR)
		return msg
	end
	return nil
end

--- Find and replace template variables in a file.
---@param path string # Path to the file
---@param vars table<string, string> # Table of variables to replace
---@return nil|string # nil on success, error message on failure
function M.findAndReplace(path, vars)
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

--- Split a markdown note into YAML front matter (inner text) and body.
--- Supports a leading --- block; if missing, returns nil, full content.
---@param content string
---@return string|nil yaml_inner Text between delimiters (no --- lines)
---@return string body Rest of file after closing ---
function M.splitNoteContent(content)
	-- Literal --- must use %- in Lua patterns (otherwise - is repetition).
	local open = "^%s*%-%-%-%s*[\r\n]"
	if not content:match(open) then
		return nil, content
	end
	local after_open = content:match("^%s*%-%-%-%s*[\r\n]+(.*)$")
	if not after_open then
		return nil, content
	end
	-- Empty YAML: closing --- is the first line after the opening delimiter
	if after_open:match("^%-%-%-%s*[\r\n]") then
		local body = after_open:match("^%-%-%-%s*[\r\n]+(.*)$")
		return "", body or ""
	end
	local yaml_inner, body = after_open:match("^(.-)[\r\n]+%-%-%-%s*[\r\n]+(.*)$")
	if not yaml_inner then
		return nil, content
	end
	return yaml_inner, body
end

--- Parse a simple YAML subset: scalar lines (key: value) and one level of lists (key: then indented - items).
---@param yaml_inner string
---@return table|nil data
---@return string[]|nil key_order
---@return string|nil err
function M.parseYamlFrontmatterBlock(yaml_inner)
	if yaml_inner == "" then
		return {}, {}
	end
	local result = {}
	local order = {}
	local lines = vim.split(yaml_inner, "\n", { plain = true })
	local i = 1
	while i <= #lines do
		local line = lines[i]
		if line:match("^%s*$") then
			i = i + 1
		else
			local key, rest = line:match("^([%w_%-]+)%s*:%s*(.*)$")
			if not key then
				return nil, nil, "invalid front matter line: " .. line
			end
			if rest == "" then
				local next_ln = lines[i + 1]
				if next_ln and next_ln:match("^%s+%-") then
					i = i + 1
					local list = {}
					while i <= #lines do
						local l = lines[i]
						local item = l:match("^%s+%-%s+(.+)$")
						if item then
							table.insert(list, item)
							i = i + 1
						else
							break
						end
					end
					table.insert(order, key)
					result[key] = list
				else
					table.insert(order, key)
					result[key] = ""
					i = i + 1
				end
			else
				table.insert(order, key)
				result[key] = rest
				i = i + 1
			end
		end
	end
	return result, order, nil
end

--- Serialize a simple front matter table back to YAML (no surrounding ---).
---@param data table
---@param key_order string[] keys in output order (new keys not listed are appended at end)
---@return string
function M.serializeFrontmatter(data, key_order)
	local seen = {}
	local order = {}
	for _, k in ipairs(key_order or {}) do
		if data[k] ~= nil then
			table.insert(order, k)
			seen[k] = true
		end
	end
	for k, _ in pairs(data) do
		if not seen[k] and data[k] ~= nil then
			table.insert(order, k)
		end
	end

	local lines = {}
	for _, key in ipairs(order) do
		local v = data[key]
		if type(v) == "table" then
			table.insert(lines, key .. ":")
			for _, item in ipairs(v) do
				table.insert(lines, "  - " .. item)
			end
		else
			table.insert(lines, key .. ": " .. tostring(v))
		end
	end
	return table.concat(lines, "\n") .. (#order > 0 and "\n" or "")
end

---@param yaml_inner string
---@param body string
---@return string
function M.buildNoteWithFrontmatter(yaml_inner, body)
	return "---\n" .. yaml_inner .. "---\n\n" .. body
end

--- Path of `file_abs` relative to the vault root, using `/` separators (for Obsidian CLI).
---@param vault_root string Absolute vault directory
---@param file_abs string Absolute path to a file
---@return string|nil rel e.g. `notes/Foo.md`, or nil if the file is not under the vault
function M.fileRelativeToVault(vault_root, file_abs)
	vault_root = vim.fs.normalize(vault_root)
	file_abs = vim.fs.normalize(file_abs)
	local rel
	if vim.fs.relpath then
		rel = vim.fs.relpath(vault_root, file_abs)
	else
		local base = vault_root
		if base:sub(-1) ~= "/" then
			base = base .. "/"
		end
		if file_abs:sub(1, #base) == base then
			rel = file_abs:sub(#base + 1)
		end
	end
	if not rel or rel == "" then
		return nil
	end
	return rel:gsub("\\", "/")
end

--- Merge or prepend YAML front matter keys into markdown content.
---@param content string
---@param updates table
---@return string|nil new_content
---@return string|nil err
function M.mergeFrontmatterIntoContent(content, updates)
	if not updates or next(updates) == nil then
		return content, nil
	end

	local yaml_inner, body = M.splitNoteContent(content)
	local data, key_order, parse_err

	if yaml_inner ~= nil then
		data, key_order, parse_err = M.parseYamlFrontmatterBlock(yaml_inner)
		if parse_err then
			return nil, parse_err
		end
	else
		data = {}
		key_order = {}
		body = content
	end

	local merged = vim.deepcopy(data)
	for k, v in pairs(updates) do
		merged[k] = v
	end
	local merged_order = vim.fn.copy(key_order)
	for k, _ in pairs(updates) do
		local found = false
		for _, ok in ipairs(merged_order) do
			if ok == k then
				found = true
				break
			end
		end
		if not found then
			table.insert(merged_order, k)
		end
	end

	local yaml_str = M.serializeFrontmatter(merged, merged_order)
	return M.buildNoteWithFrontmatter(yaml_str, body or ""), nil
end

return M
