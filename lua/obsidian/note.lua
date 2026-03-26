-- Note API
local NoteAPI = {}

local log = require("obsidian.log")
local obsidian = require("obsidian")
local encode_property_value = require("obsidian.note_properties").encode_property_value

---@class NoteProperty
---@field name string
---@field value string
---@field type string #text|list|number|checkbox|date|datetime

---@class NoteOptions
---@field fileName string # Filename for the note
---@field path string # Path relative to the vault where file should be created
---@field templateName string # Name of the template to use
---@field templateVariables table<string, string> # Map of Template variables to substitue
---@field properties NoteProperty[] # Optional fields merged into YAML properties after template copy

-- Note creator
---@param noteOptions NoteOptions
---@return string|nil filePath, string|nil fileName
function NoteAPI.createNoteFromTemplate(noteOptions)
	local util = require("obsidian.util")
	local vault = obsidian.ensure_vault_dir({ log_scope = "createNoteFromTemplate" })
	if not vault then
		return nil
	end
	local cfg = obsidian.getConfig()
	local filename = noteOptions.fileName .. ".md"

	local template_dir = cfg.template_dir or "templates"
	local templatePath = vim.fs.joinpath(vault, template_dir, noteOptions.templateName .. ".md")
	if not util.checkFileExists(templatePath) then
		log.append("createNoteFromTemplate: template missing\n" .. templatePath .. "\n")
		vim.notify("Template " .. templatePath .. " does not exist", vim.log.levels.ERROR)
		return nil
	end

	local dest_dir = vim.fs.joinpath(vault, noteOptions.path or "")
	vim.fn.mkdir(dest_dir, "p")

	local err = util.copyFileAndRename(templatePath, dest_dir, filename)
	if err ~= nil then
		log.append("createNoteFromTemplate: copy failed\n" .. tostring(err) .. "\n")
		vim.notify("Could not create with template" .. templatePath .. " Err: " .. err, vim.log.levels.ERROR)
		return nil
	end

	local note_file = vim.fs.joinpath(dest_dir, filename)
	local replaceErr = util.findAndReplace(note_file, noteOptions.templateVariables)

	if replaceErr ~= nil then
		log.append("createNoteFromTemplate: template var substitution failed\n" .. tostring(replaceErr) .. "\n")
		vim.notify("Could not substitute template vars Err: " .. replaceErr, vim.log.levels.ERROR)
		return nil
	end

	vim.api.nvim_command("edit " .. vim.fn.fnameescape(note_file))
	return note_file, filename
end

--- Tell the Obsidian app to open/focus a note (`obsidian open path=…`).
--- Uses the **active buffer’s** file path unless `note_path` is given (absolute).
---@param note_path string|nil
---@return boolean
function NoteAPI.setActiveFile(note_path)
	local vault = obsidian.ensure_vault_dir({ log_scope = "setActiveFile" })
	if not vault then
		return false
	end
	local util = require("obsidian.util")

	local abs = note_path or vim.api.nvim_buf_get_name(0)
	if abs == nil or abs == "" then
		vim.notify("setActiveFile: no path and buffer has no file", vim.log.levels.ERROR)
		return false
	end

	abs = vim.fs.normalize(abs)
	local rel = util.fileRelativeToVault(vault, abs)
	if not rel then
		log.append("setActiveFile: file not under vault\n" .. abs .. "\n")
		vim.notify("setActiveFile: file is not inside obsidian_vault_dir", vim.log.levels.ERROR)
		return false
	end

	local cli = require("obsidian.cli")
	local openCmd = "open path=" .. vim.fn.shellescape(rel)
	return cli.runCommand(openCmd) ~= nil
end

--- Rename the currently active note
---@param new_name string
---@param note_path string|nil
---@return boolean
function NoteAPI.RenameNote(new_name, note_path)
	local vault = obsidian.ensure_vault_dir({ log_scope = "RenameNote" })
	if not vault then
		return false
	end
	local util = require("obsidian.util")

	local abs = note_path or vim.api.nvim_buf_get_name(0)
	if abs == nil or abs == "" then
		vim.notify("RenameNote: no path and buffer has no file", vim.log.levels.ERROR)
		return false
	end

	abs = vim.fs.normalize(abs)
	local rel = util.fileRelativeToVault(vault, abs)
	if not rel then
		log.append("RenameNote: file not under vault\n" .. abs .. "\n")
		vim.notify("RenameNote: file is not inside obsidian_vault_dir", vim.log.levels.ERROR)
		return false
	end
	local cli = require("obsidian.cli")
	local openCmd = "rename path=" .. vim.fn.shellescape(rel) .. " name=" .. vim.fn.shellescape(new_name)
	-- TODO: this also needs to update the ID
	return cli.runCommand(openCmd) ~= nil
end

--- Update the properties of the note
---@param properties NoteProperty[] # Fields merged into YAML properties after template copy
---@param note_path string # Path to Note
function NoteAPI.UpdateNoteProperties(properties, note_path)
	local cli = require("obsidian.cli")
	for _, property in ipairs(properties or {}) do
		local raw = encode_property_value(property.value)
		--- runTextCommand returns stdout on success, nil if the command failed.
		local out = cli.runTextCommand(
			"property:set name="
				.. vim.fn.shellescape(property.name)
				.. " value="
				.. vim.fn.shellescape(raw)
				.. " type="
				.. vim.fn.shellescape(property.type)
				.. " path="
				.. vim.fn.shellescape(note_path)
		)
		if out == nil then
			log.append("Failed to set property: " .. property.name .. "\n")
		end
	end
end

--- Get note properties
---@param note_path string|nil # FilePath relative to directory
---@param properties string[] # Properties to search for
---@return table<string,string> # Property key matched to value
function NoteAPI.GetNoteProperties(note_path, properties)
	local target = note_path
	local vault = obsidian.ensure_vault_dir()
	if not vault then
		return {}
	end

	if not note_path then
		target = require("obsidian.util").get_relative_path(vim.api.nvim_buf_get_name(0), vault)
	end

	local cli = require("obsidian.cli")
	local result = cli.runJsonCommand(string.format('properties format=json path="%s"', target))
	if not result then
		return {}
	end

	local out = {}
	for _, prop in ipairs(properties) do
		if result[prop] ~= nil then
			out[prop] = result[prop]
		end
	end
	return out
end

---@param raw table|nil
---@return table[]
local function normalize_tasks_json(raw)
	if raw == nil then
		return {}
	end
	if type(raw) ~= "table" then
		return {}
	end
	if vim.islist and vim.islist(raw) then
		return raw
	end
	if raw[1] ~= nil then
		return raw
	end
	if raw.tasks ~= nil and type(raw.tasks) == "table" then
		return raw.tasks
	end
	if raw.status ~= nil and raw.text ~= nil then
		return { raw }
	end
	return {}
end

---@param tasks table[]
---@param note_rel string
---@param vault_dir string
---@return table[]
local function filter_tasks_for_note(tasks, note_rel, vault_dir)
	local util = require("obsidian.util")
	local want = vim.fs.normalize(note_rel):gsub("\\", "/")
	local out = {}
	for _, t in ipairs(tasks) do
		if type(t) == "table" then
			local tf = t.file
			if tf == nil then
				out[#out + 1] = t
			else
				local s = tostring(tf):gsub("\\", "/")
				local rel ---@type string|nil
				if s:sub(1, 1) == "/" or s:match("^%a:/") then
					rel = util.fileRelativeToVault(vault_dir, s)
				else
					rel = s
				end
				if rel and vim.fs.normalize(rel):gsub("\\", "/") == want then
					out[#out + 1] = t
				end
			end
		end
	end
	if #out == 0 and #tasks > 0 then
		return tasks
	end
	return out
end

---@param a string|nil
---@param b string|nil
---@return boolean
local function task_status_eq(a, b)
	a = a == nil and "" or tostring(a)
	b = b == nil and "" or tostring(b)
	return vim.trim(a) == vim.trim(b)
end

---@param tasks table[]
---@param filter_char string|nil
---@return table[]
local function filter_tasks_by_status(tasks, filter_char)
	if filter_char == nil or filter_char == "" then
		return tasks
	end
	local out = {}
	for _, t in ipairs(tasks) do
		if task_status_eq(t.status, filter_char) then
			out[#out + 1] = t
		end
	end
	return out
end

--- Strip leading markdown task prefix so we do not duplicate `task.status` (e.g. `- [x] foo` → `foo`).
---@param line string|nil
---@return string
local function task_body_only(line)
	line = vim.trim(line or "")
	local body = select(2, line:match("^%-%s*%[(.-)%]%s*(.*)$"))
	if body ~= nil then
		return vim.trim(body)
	end
	return line
end

--- One line per task: markdown-style `- [status] body` (body from `task.text` without duplicating the checkbox).
---@param task table
---@return string
local function format_task_popup_line(task)
	local body = task_body_only(task.text or "?")
	local short = vim.fn.strcharpart(body, 0, 72)
	if vim.fn.strchars(body) > 72 then
		short = short .. "…"
	end
	return string.format("- [%s] %s", tostring(task.status or " "), short)
end

local TASK_POPUP_HEADER_LINES = 2

--- Floating buffer: list tasks, `<CR>` pick status, `r` refresh, `q` close.
---@param state { tasks: table[], fetch: fun(): table[] }
---@param on_status fun(task: table, refresh: fun())  e.g. `vim.ui.select` then call `refresh()` after a successful CLI update
local function open_task_popup_buffer(state, on_status)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false

	local function task_lines(tasks)
		local lines = {
			"Obsidian tasks  —  <Enter> set status   r refresh   q close",
			string.rep("─", math.min(72, vim.o.columns - 8)),
		}
		for _, t in ipairs(tasks) do
			lines[#lines + 1] = format_task_popup_line(t)
		end
		return lines
	end

	local function redraw()
		local lines = task_lines(state.tasks)
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.bo[buf].filetype = "markdown"
	end

	redraw()

	local n = #state.tasks
	local height = math.max(3, math.min(TASK_POPUP_HEADER_LINES + n + 1, vim.o.lines - 4))
	local width = math.min(88, vim.o.columns - 4)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
	}
	local ver = vim.version()
	if ver and (ver.major > 0 or ver.minor >= 9) then
		win_opts.title = " Tasks "
		win_opts.title_pos = "center"
	end

	local win = vim.api.nvim_open_win(buf, true, win_opts)
	vim.wo[win].wrap = true
	vim.wo[win].cursorline = true

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function refresh()
		local next_tasks = state.fetch()
		if not next_tasks or #next_tasks == 0 then
			vim.notify("No tasks left in this note.", vim.log.levels.INFO)
			close()
			return
		end
		state.tasks = next_tasks
		redraw()
		local last = TASK_POPUP_HEADER_LINES + #state.tasks
		local cur = vim.api.nvim_win_get_cursor(win)
		if cur[1] > last then
			vim.api.nvim_win_set_cursor(win, { last, 0 })
		end
	end

	local function current_task()
		local lnum = vim.api.nvim_win_get_cursor(win)[1]
		local idx = lnum - TASK_POPUP_HEADER_LINES
		if idx < 1 or idx > #state.tasks then
			return nil
		end
		return state.tasks[idx]
	end

	vim.keymap.set("n", "<CR>", function()
		local t = current_task()
		if not t then
			return
		end
		on_status(t, refresh)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "r", refresh, { buffer = buf, silent = true })

	vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })

	vim.api.nvim_win_set_cursor(win, { TASK_POPUP_HEADER_LINES + 1, 0 })
end

--- Run Obsidian CLI: `task path="…" line=… status="…"`.
---@param note_rel string
---@param line_nr integer|string
---@param status_key string
---@return boolean
local function run_task_status_update(note_rel, line_nr, status_key)
	local cli = require("obsidian.cli")
	local util = require("obsidian.util")
	local line_part = tostring(tonumber(line_nr) or line_nr)
	local cmd = string.format(
		'task path="%s" line=%s status="%s"',
		util.escapeObsidianCliDoubleQuoted(note_rel),
		line_part,
		util.escapeObsidianCliDoubleQuoted(status_key)
	)
	local out = cli.runTextCommand(cmd)
	if out == nil then
		log.append("UpdateNoteTask: task command failed: " .. cmd .. "\n")
		return false
	end
	return true
end

--- Interactively pick a task in the note, then a new checkbox status, and update via CLI.
---
--- JSON shape from `tasks path="…" format=json`:
--- `[{ "status": "x", "text": "- [x] …", "file": "…", "line": "147" }, …]`
---
---@param note_path string|nil Relative path to the note in the vault; defaults to the current buffer.
---@param requested_task_char string|nil If set, only tasks whose current `status` match (e.g. `" "` or `"x"`).
---@param opts { statuses?: { key: string, label: string }[] }|nil Optional status list for the second prompt (overrides `setup({ task_statuses = … })`).
function NoteAPI.UpdateNoteTask(note_path, requested_task_char, opts)
	opts = opts or {}
	local vault = obsidian.ensure_vault_dir()
	if not vault then
		return
	end
	local cfg = obsidian.getConfig()
	local util = require("obsidian.util")

	local target = note_path
	if not target or target == "" then
		target = util.get_relative_path(vim.api.nvim_buf_get_name(0), vault)
	end

	local cli = require("obsidian.cli")
	local task_cmd = string.format('tasks path="%s" format="json"', util.escapeObsidianCliDoubleQuoted(target))
	if requested_task_char and requested_task_char ~= "" then
		task_cmd = task_cmd
			.. string.format(' status="%s"', util.escapeObsidianCliDoubleQuoted(requested_task_char))
	end

	local task_table = cli.runJsonCommand(task_cmd)
	local tasks = normalize_tasks_json(task_table)
	tasks = filter_tasks_for_note(tasks, target, vault)
	tasks = filter_tasks_by_status(tasks, requested_task_char)

	if #tasks == 0 then
		vim.notify("No tasks found for this note.", vim.log.levels.INFO)
		return
	end

	local note_abs = vim.fs.normalize(vim.fs.joinpath(vault, target))

	--- Reload every normal buffer that is editing this note (after CLI changes on disk).
	--- Uses `:edit!` instead of `:checktime` so the file refreshes immediately; `checktime`/`autoread`
	--- can wait until the next redraw or cursor movement.
	local function reload_note_file_buffers()
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
				local n = vim.api.nvim_buf_get_name(b)
				if n ~= "" and vim.fs.normalize(n) == note_abs then
					if vim.bo[b].modified then
						vim.notify(
							"Note has unsaved changes; skipped reload after task update.",
							vim.log.levels.WARN
						)
					else
						vim.api.nvim_buf_call(b, function()
							vim.cmd.edit({ bang = true })
						end)
					end
				end
			end
		end
		vim.cmd.redraw()
	end

	local statuses = opts.statuses or cfg.task_statuses

	local function fetch_tasks()
		local task_table = cli.runJsonCommand(task_cmd)
		local t = normalize_tasks_json(task_table)
		t = filter_tasks_for_note(t, target, vault)
		t = filter_tasks_by_status(t, requested_task_char)
		return t
	end

	local function apply_status(task, status_row)
		if not status_row then
			return false
		end
		local ok = run_task_status_update(target, task.line, status_row.key)
		if ok then
			vim.notify("Task updated.", vim.log.levels.INFO)
			reload_note_file_buffers()
			return true
		end
		vim.notify("Could not update task (see obsidian log).", vim.log.levels.ERROR)
		return false
	end

	local function pick_status(task, refresh_popup)
		vim.ui.select(statuses, {
			prompt = "New status",
			format_item = function(row)
				return row.label
			end,
		}, function(choice)
			if choice == nil then
				return
			end
			if apply_status(task, choice) and refresh_popup then
				refresh_popup()
			end
		end)
	end

	local state = { tasks = tasks, fetch = fetch_tasks }
	open_task_popup_buffer(state, pick_status)
end

return NoteAPI
