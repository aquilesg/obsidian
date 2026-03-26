--- Create notes from vault templates using `setup`-supplied `directories` / `template_names`.
---
--- Also stores `note_properties` on config for templates / callers that need YAML key names.
---
--- @module 'obsidian.note_creation'

local M = {}

--- `My Title` → `MyTitle` style id (filename stem).
---@param title string
---@return string
function M.camel_case_title(title)
	local result = title:gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
	result = result:gsub('[/\\%*%?%:"<>|]', "")
	result = result
		:gsub("(%a)([%w_']*)", function(first, rest)
			return first:upper() .. rest:lower()
		end)
		:gsub("%s+", "")
	return result
end

--- Create a note for a **template type key** (e.g. `"WorkOncallTask"`), resolving `directories[key]` and `template_names[key]` from `obsidian.setup({ ... })`.
---
---@param type_key string # key into `directories` / `template_names`
function M.create_for_type(type_key)
	M.create_with_options({
		template_type = type_key,
		prompt_for_type = false,
	})
end

--- Find the type key whose template **file** name matches `template_name` (value in `template_names`), then create.
--- Use when you only have the template string, e.g. `"WorkEvent"` for `WorkEvents` → `"WorkEvent"`.
---
---@param template_name string
function M.create_by_template_name(template_name)
	local cfg = require("obsidian").getConfig()
	local template_names = cfg.template_names
	if not template_names then
		vim.notify("obsidian: set template_names in setup()", vim.log.levels.ERROR)
		return
	end
	for k, v in pairs(template_names) do
		if v == template_name then
			M.create_for_type(k)
			return
		end
	end
	vim.notify("obsidian: unknown template name: " .. tostring(template_name), vim.log.levels.WARN)
end

---@class obsidian.note_creation.WithOptions
---@field prompt_for_type boolean|nil # if true, `vim.ui.select` over type keys
---@field template_type string|nil # key into directories / template_names when not prompting
---@field insert_link boolean|nil # insert `[[id|title]]` at cursor before creating

--- Interactive create: optional type picker, title input, then `createNoteFromTemplate`.
---
---@param opts obsidian.note_creation.WithOptions|nil
function M.create_with_options(opts)
	opts = opts or {}
	local cfg = require("obsidian").getConfig()
	local directories = cfg.directories
	local template_names = cfg.template_names
	if not directories or not template_names then
		vim.notify(
			"obsidian: set directories and template_names in setup()",
			vim.log.levels.ERROR
		)
		return
	end

	local Note = require("obsidian.note")

	local template_keys = {}
	for k, _ in pairs(template_names) do
		template_keys[#template_keys + 1] = k
	end
	table.sort(template_keys)

	local function create_for_choice(choice)
		if not choice then
			return
		end
		local user_title = vim.fn.input({ prompt = choice .. " title: " })
		if not user_title or user_title == "" then
			vim.notify("Note title cannot be empty", vim.log.levels.WARN)
			return
		end
		local user_id = M.camel_case_title(user_title)
		if opts.insert_link then
			local text = " [[" .. user_id .. "|" .. user_title .. "]]"
			local cursor = vim.api.nvim_win_get_cursor(0)
			local row, col = cursor[1], cursor[2]
			local current_line = vim.api.nvim_get_current_line()
			local new_line = string.sub(current_line, 1, col)
				.. text
				.. string.sub(current_line, col + 1)
			vim.api.nvim_set_current_line(new_line)
			vim.api.nvim_win_set_cursor(0, { row, col + #text })
		end
		local dir = directories[choice]
		local tmpl = template_names[choice]
		if not dir or not tmpl then
			vim.notify(
				"obsidian: missing directory or template for " .. tostring(choice),
				vim.log.levels.ERROR
			)
			return
		end
		Note.createNoteFromTemplate({
			fileName = user_id,
			path = dir,
			templateName = tmpl,
			templateVariables = {
				id = user_id,
				title = user_title,
			},
		})
	end

	if opts.prompt_for_type then
		vim.ui.select(template_keys, {
			prompt = "Document type",
		}, create_for_choice)
	else
		create_for_choice(opts.template_type)
	end
end

return M
