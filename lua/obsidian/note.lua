-- Note API
local NoteAPI = {}

local log = require("obsidian.log")

---@class NoteOptions
---@field fileName string # Filename for the note
---@field path string # Path relative to the vault where file should be created
---@field templateName string # Name of the template to use
---@field templateVariables table<string, string> # Map of Template variables to substitue
---@field frontmatter? table # Optional fields merged into YAML front matter after template copy

-- Note creator
---@param noteOptions NoteOptions
---@return string|nil fileName # File name of created note
function NoteAPI.createNoteFromTemplate(noteOptions)
	local util = require("obsidian.util")
	local cfg = require("obsidian").getConfig()
	if not cfg.obsidian_vault_dir then
		log.append("createNoteFromTemplate: obsidian_vault_dir not configured\n")
		vim.notify("obsidian_vault_dir not configured", vim.log.levels.ERROR)
		return nil
	end

	local template_dir = cfg.template_dir or "templates"
	local templatePath = vim.fs.joinpath(cfg.obsidian_vault_dir, template_dir, noteOptions.templateName)
	if not util.checkFileExists(templatePath) then
		log.append("createNoteFromTemplate: template missing\n" .. templatePath .. "\n")
		vim.notify("Template " .. templatePath .. " does not exist", vim.log.levels.ERROR)
		return nil
	end

	local dest_dir = vim.fs.joinpath(cfg.obsidian_vault_dir, noteOptions.path or "")
	vim.fn.mkdir(dest_dir, "p")

	local err = util.copyFileAndRename(templatePath, dest_dir, noteOptions.fileName)
	if err ~= nil then
		log.append("createNoteFromTemplate: copy failed\n" .. tostring(err) .. "\n")
		vim.notify("Could not create with template" .. templatePath .. " Err: " .. err, vim.log.levels.ERROR)
		return nil
	end

	local note_file = vim.fs.joinpath(dest_dir, noteOptions.fileName)
	local replaceErr = util.findAndReplace(note_file, noteOptions.templateVariables)

	if replaceErr ~= nil then
		log.append("createNoteFromTemplate: template var substitution failed\n" .. tostring(replaceErr) .. "\n")
		vim.notify("Could not substitute template vars Err: " .. replaceErr, vim.log.levels.ERROR)
		return nil
	end

	if noteOptions.frontmatter and next(noteOptions.frontmatter) then
		local fin = io.open(note_file, "r")
		if not fin then
			vim.notify("Could not read new note for front matter: " .. note_file, vim.log.levels.ERROR)
			return nil
		end
		local content = fin:read("*a")
		fin:close()

		local new_content, fm_err = util.mergeFrontmatterIntoContent(content, noteOptions.frontmatter)
		if fm_err then
			log.append("createNoteFromTemplate: front matter merge failed\n" .. tostring(fm_err) .. "\n")
			vim.notify(fm_err, vim.log.levels.ERROR)
			return nil
		end
		local fout = io.open(note_file, "w")
		if not fout then
			vim.notify("Could not write note after front matter merge: " .. note_file, vim.log.levels.ERROR)
			return nil
		end
		fout:write(new_content)
		fout:close()
	end
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

return NoteAPI
