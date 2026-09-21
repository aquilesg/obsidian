--- TaskNotes Pomodoro control via the Obsidian CLI.
---
--- `start` runs a session for an open note (its filename, minus the extension, is used as the
--- TaskNotes `title=`). It scans every loaded buffer for vault notes; with one it uses that note,
--- with several it prompts you to pick. `stop`, `pause`, `resume` and `status` act on the running
--- session and need no note. `goto` opens the note the running session is tracking.
---
--- Call `setup()` eagerly (e.g. from your statusline config) so the background poll keeps
--- `M.statusline()` fresh.
---
--- @module 'obsidian.pomodoro'

local cli = require("obsidian.cli")
local util = require("obsidian.util")

local M = {}

-- Actions the CLI understands; `goto` is handled locally from the cached session note.
local CLI_ACTIONS = { "start", "stop", "pause", "resume", "status" }

M.actions = vim.list_extend(vim.deepcopy(CLI_ACTIONS), { "goto" })

--- @class obsidian.pomodoro.SetupOpts
--- @field vault? string # CLI `vault=` name; defaults to the basename of `obsidian_vault_dir`
--- @field poll_ms? integer # how often the background poll resyncs with the CLI, default 15000
--- @field keymaps? boolean # register the `<prefix>{s,e,p,r,i,g}` mappings, default true
--- @field keymap_prefix? string # default `<leader>op`

-- POLL_MS only needs to be frequent enough to catch session transitions (work -> break) started
-- outside Neovim; we count down locally between polls.
local DEFAULTS = {
	vault = nil,
	poll_ms = 15000,
	keymaps = true,
	keymap_prefix = "<leader>op",
}

local options = vim.deepcopy(DEFAULTS)

-- Cached session state for the statusline, so a statusline component can render without shelling
-- out to the Obsidian CLI on every redraw. `remaining` is the seconds left as of `synced_at`;
-- `M.remaining_now()` counts down from there.
M.cache = {
	status = "stopped", -- "running" | "paused" | "stopped"
	remaining = 0,
	synced_at = 0,
	type = nil,
	-- Note the session is tracking: `note_id` is the filename stem (TaskNotes `title=`),
	-- `note_path` is vault-relative. Both nil with no session.
	note_id = nil,
	note_path = nil,
	alerted = false, -- whether the "1 minute left" warning has fired this session
}

--- CLI `vault=` name: the configured value, else the vault directory's basename.
--- @return string|nil
local function vault_name()
	if options.vault and options.vault ~= "" then
		return options.vault
	end
	local dir = require("obsidian").get_vault_dir()
	return dir and vim.fs.basename(dir) or nil
end

--- @param action string
--- @param title string|nil # TaskNotes task title, for `start`
--- @return string[]
local function pomodoro_args(action, title)
	local args = { "tasknotes:pomodoro" }
	local vault = vault_name()
	if vault then
		args[#args + 1] = "vault=" .. vault
	end
	args[#args + 1] = "action=" .. action
	if title then
		args[#args + 1] = "title=" .. title
	end
	return args
end

-- TaskNotes title for a buffer: its filename without the extension.
local function buf_title(buf)
	return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
end

-- Loaded, listed buffers backed by a markdown note inside the vault.
local function note_buffers()
	local bufs = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
			local name = vim.api.nvim_buf_get_name(buf)
			if name ~= "" and name:match("%.md$") and util.isBufferInVault(buf) then
				table.insert(bufs, buf)
			end
		end
	end
	return bufs
end

-- Resolve the note buffer to start a session for and pass it to `cb`. With a single open note we
-- use it directly; with several we prompt. `cb` receives nil when there are no notes open or the
-- prompt is dismissed.
local function pick_note_buffer(cb)
	local bufs = note_buffers()
	if #bufs <= 1 then
		cb(bufs[1])
		return
	end
	vim.ui.select(bufs, {
		prompt = "Pomodoro: select a note",
		format_item = buf_title,
	}, cb)
end

local function fmt_time(secs)
	secs = math.floor(tonumber(secs) or 0)
	return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- Coarse minute display for the statusline, rounded up so it changes only once a minute rather
-- than flickering every second (e.g. 25:00 and 24:01 -> "25m").
local function fmt_minutes(secs)
	secs = math.floor(tonumber(secs) or 0)
	return string.format("%dm", math.ceil(secs / 60))
end

-- vim.json.decode turns JSON null into vim.NIL (userdata, and truthy), so `foo or default` won't
-- catch it. Fall back to `default` for nil and vim.NIL.
local function val(v, default)
	if v == nil or v == vim.NIL then
		return default
	end
	return v
end

-- One-shot timer that fires the "1 minute left" warning. Re-armed on every cache update, so
-- pauses/resumes and sessions started outside Neovim are tracked; only running sessions with more
-- than a minute left get a timer.
local alert_timer

local function clear_alert_timer()
	if alert_timer then
		alert_timer:stop()
		alert_timer:close()
		alert_timer = nil
	end
end

local function fire_alert()
	M.cache.alerted = true
	local what = M.cache.type and (M.cache.type .. " ") or ""
	vim.notify("1 minute left in your " .. what .. "session", vim.log.levels.WARN, { title = "󰔟 Pomodoro" })
end

-- (Re)arm the warning for when the running session hits one minute remaining.
local function schedule_alert()
	clear_alert_timer()
	if M.cache.status ~= "running" or M.cache.alerted then
		return
	end
	local lead = M.remaining_now() - 60
	if lead <= 0 then
		if M.remaining_now() > 0 then
			fire_alert()
		end
		return
	end
	alert_timer = vim.uv.new_timer()
	if alert_timer then
		alert_timer:start(
			lead * 1000,
			0,
			vim.schedule_wrap(function()
				if M.cache.status == "running" and not M.cache.alerted then
					fire_alert()
				end
			end)
		)
	end
end

-- Refresh the statusline cache from a decoded pomodoro state.
local function update_cache(state)
	local session = val(state.currentSession)
	if state.isRunning then
		M.cache.status = "running"
	elseif session then
		M.cache.status = "paused"
	else
		M.cache.status = "stopped"
	end
	M.cache.remaining = math.floor(tonumber(val(state.timeRemaining, 0)) or 0)
	M.cache.synced_at = os.time()
	M.cache.type = session and val(session.type, nil) or nil
	local task = session and val(session.task, {}) or {}
	M.cache.note_id = val(task.title, nil)
	M.cache.note_path = val(task.path, nil)
	-- A fresh session (more than a minute on the clock) re-arms the warning; this also covers
	-- work -> break transitions, which reset the timer.
	if M.cache.remaining > 60 then
		M.cache.alerted = false
	end
	schedule_alert()
end

--- Seconds left right now: count down locally from the last sync while running.
--- @return integer
function M.remaining_now()
	if M.cache.status == "running" then
		local left = M.cache.remaining - (os.time() - M.cache.synced_at)
		return left > 0 and left or 0
	end
	return M.cache.remaining
end

--- Statusline string for a statusline component; empty when there is no active session.
--- @return string
function M.statusline()
	if M.cache.status == "stopped" then
		return ""
	end
	local icon = M.cache.status == "running" and "󰔟" or "󰏤"
	local label = M.cache.type and (" " .. M.cache.type) or ""
	return string.format("%s %s%s", icon, fmt_minutes(M.remaining_now()), label)
end

-- Refresh the cache from the CLI without any notification (background poll).
local function refresh_cache()
	cli.runJsonCommandAsync(pomodoro_args("status"), function(state)
		if state then
			update_cache(state)
		end
	end, true)
end

-- Pretty-print the pomodoro state JSON as a notification.
local function notify_state(state)
	local lines = {}
	local session = val(state.currentSession)
	local header
	if state.isRunning then
		header = "󰔟 Pomodoro — Running"
	elseif session then
		header = "󰔟 Pomodoro — Paused"
	else
		header = "󰔟 Pomodoro — Stopped"
	end
	if session then
		local task = val(session.task, {})
		table.insert(lines, "Task:  " .. val(task.title, "—"))
		table.insert(
			lines,
			string.format("Type:  %s (%s min)", val(session.type, "?"), val(session.plannedDuration, "?"))
		)
		table.insert(lines, "Left:  " .. fmt_time(state.timeRemaining))
	else
		table.insert(lines, "No active session")
		if state.timeRemaining then
			table.insert(lines, "Ready: " .. fmt_time(state.timeRemaining))
		end
	end
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = header })
end

-- Run a pomodoro action via the CLI and show the result. `title` scopes a `start` to a note;
-- `reload_buf`, if given, is reloaded once the session begins so TaskNotes' frontmatter writes
-- show up in the buffer.
local function run_action(action, title, reload_buf)
	cli.runJsonCommandAsync(pomodoro_args(action, title), function(state, err)
		if not state then
			vim.notify("Pomodoro failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return
		end
		if reload_buf and vim.api.nvim_buf_is_loaded(reload_buf) then
			vim.api.nvim_buf_call(reload_buf, function()
				vim.cmd("silent edit")
			end)
		end
		update_cache(state)
		notify_state(state)
	end)
end

--- Absolute path of the note the session is tracking, from `note_path` (or `note_id` when the
--- CLI reports no path).
--- @return string|nil
local function tracked_note_file()
	local dir = require("obsidian").get_vault_dir()
	if not dir then
		return nil
	end
	local rel = M.cache.note_path or (M.cache.note_id and (M.cache.note_id .. ".md"))
	return rel and (dir .. "/" .. rel) or nil
end

--- Open the note the current session is tracking. Resyncs with the CLI first so a session started
--- outside Neovim, or since the last poll, is picked up.
function M.goto_note()
	cli.runJsonCommandAsync(pomodoro_args("status"), function(state, err)
		if not state then
			vim.notify("Pomodoro failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return
		end
		update_cache(state)
		local file = tracked_note_file()
		if not file then
			vim.notify("Pomodoro: no session note to open", vim.log.levels.WARN)
			return
		end
		vim.cmd("edit " .. vim.fn.fnameescape(file))
	end)
end

--- Run a pomodoro action and show the result.
--- @param action string|nil # one of `M.actions`, default "status"
function M.pomodoro(action)
	action = action or "status"
	if not vim.tbl_contains(M.actions, action) then
		vim.notify("Pomodoro: unknown action '" .. action .. "'", vim.log.levels.ERROR)
		return
	end

	-- `start` acts on an open note, chosen from the loaded buffers (prompting if there is more
	-- than one); the other actions need no note. Resolve the note first, then run the command
	-- with the chosen title.
	if action == "goto" then
		M.goto_note()
		return
	end

	if action ~= "start" then
		run_action(action)
		return
	end

	pick_note_buffer(function(buf)
		if not buf then
			vim.notify("Pomodoro: no note open to start a session for", vim.log.levels.WARN)
			return
		end
		-- Persist any pending edits first so the session starts from what's on screen;
		-- run_action reloads the buffer afterward.
		if vim.bo[buf].modified then
			vim.api.nvim_buf_call(buf, function()
				vim.cmd("silent write")
			end)
		end
		run_action(action, buf_title(buf), buf)
	end)
end

local poll_timer

--- Register the `:Pomodoro` command, the keymaps, and the background poll.
--- @param opts? obsidian.pomodoro.SetupOpts
function M.setup(opts)
	options = vim.tbl_extend("force", vim.deepcopy(DEFAULTS), opts or {})

	vim.api.nvim_create_user_command("Pomodoro", function(args)
		M.pomodoro(args.args ~= "" and args.args or "status")
	end, {
		nargs = "?",
		complete = function(arg_lead)
			return vim.tbl_filter(function(a)
				return a:find(arg_lead, 1, true) == 1
			end, M.actions)
		end,
		desc = "Control TaskNotes Pomodoro (start|stop|pause|resume|status|goto)",
	})

	if options.keymaps then
		local keymaps = {
			{ "s", "start", "Pomodoro start (open note)" },
			{ "e", "stop", "Pomodoro stop" },
			{ "p", "pause", "Pomodoro pause" },
			{ "r", "resume", "Pomodoro resume" },
			{ "i", "status", "Pomodoro status" },
			{ "g", "goto", "Pomodoro go to tracked note" },
		}
		for _, km in ipairs(keymaps) do
			local suffix, action, desc = km[1], km[2], km[3]
			vim.keymap.set("n", options.keymap_prefix .. suffix, function()
				M.pomodoro(action)
			end, { desc = desc })
		end
	end

	-- Keep the statusline roughly in sync with the real session. We count down locally between
	-- polls, so a coarse interval is enough.
	if poll_timer then
		poll_timer:stop()
		poll_timer:close()
		poll_timer = nil
	end
	local timer = vim.uv.new_timer()
	if timer then
		poll_timer = timer
		timer:start(options.poll_ms, options.poll_ms, vim.schedule_wrap(refresh_cache))
	end
end

return M
