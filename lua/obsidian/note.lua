-- Note API
local NoteAPI = {}

local log = require("obsidian.log")

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
	local cfg = require("obsidian").getConfig()
	local filename = noteOptions.fileName .. ".md"
	if not cfg.obsidian_vault_dir then
		log.append("createNoteFromTemplate: obsidian_vault_dir not configured\n")
		vim.notify("obsidian_vault_dir not configured", vim.log.levels.ERROR)
		return nil
	end

	local template_dir = cfg.template_dir or "templates"
	local templatePath = vim.fs.joinpath(cfg.obsidian_vault_dir, template_dir, noteOptions.templateName .. ".md")
	if not util.checkFileExists(templatePath) then
		log.append("createNoteFromTemplate: template missing\n" .. templatePath .. "\n")
		vim.notify("Template " .. templatePath .. " does not exist", vim.log.levels.ERROR)
		return nil
	end

	local dest_dir = vim.fs.joinpath(cfg.obsidian_vault_dir, noteOptions.path or "")
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
	local cfg = require("obsidian").getConfig()
	local util = require("obsidian.util")
	if not cfg.obsidian_vault_dir then
		log.append("setActiveFile: obsidian_vault_dir not configured\n")
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
		return false
	end

	local abs = note_path or vim.api.nvim_buf_get_name(0)
	if abs == nil or abs == "" then
		vim.notify("setActiveFile: no path and buffer has no file", vim.log.levels.ERROR)
		return false
	end

	abs = vim.fs.normalize(abs)
	local rel = util.fileRelativeToVault(cfg.obsidian_vault_dir, abs)
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
	local cfg = require("obsidian").getConfig()
	local util = require("obsidian.util")
	if not cfg.obsidian_vault_dir then
		log.append("setActiveFile: obsidian_vault_dir not configured\n")
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
		return false
	end

	local abs = note_path or vim.api.nvim_buf_get_name(0)
	if abs == nil or abs == "" then
		vim.notify("setActiveFile: no path and buffer has no file", vim.log.levels.ERROR)
		return false
	end

	abs = vim.fs.normalize(abs)
	local rel = util.fileRelativeToVault(cfg.obsidian_vault_dir, abs)
	if not rel then
		log.append("setActiveFile: file not under vault\n" .. abs .. "\n")
		vim.notify("setActiveFile: file is not inside obsidian_vault_dir", vim.log.levels.ERROR)
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
		local err = cli.runTextCommand(
			"property:set name='"
				.. property.name
				.. "' value='"
				.. property.value
				.. "' type='"
				.. property.type
				.. "' path='"
				.. note_path
		)
		if err then
			log.append("Failed to set property: " .. property.name .. " err: " .. tostring(err))
		end
	end
end

--- Get note properties
---@param note_path string # FilePath relative to directory
---@param property_name string
---@return table # Property value
function NoteAPI.GetNoteProperty(note_path, property_name)
	local target = note_path
	local cfg = require("obsidian").getConfig()
	if not cfg.obsidian_vault_dir then
		vim.notify("obsidian_vault_dir is not configured", vim.log.levels.ERROR)
		return {}
	end

	if not note_path then
		target = require("obsidian.util").get_relative_path(vim.api.nvim_buf_get_name(0), cfg.obsidian_vault_dir)
	end

	local cli = require("obsidian.cli")
	local result = cli.runTextCommand(string.format('property:read name="%s" path="%s"', property_name, target))

	local lines = {}
	if result then
		for line in tostring(result):gmatch("[^\r\n]+") do
			table.insert(lines, line)
		end
	end
	return lines
end

return NoteAPI
