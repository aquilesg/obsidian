-- Note API
local NoteAPI = {}

---@class NoteOptions
---@field fileName string # Filename for the note
---@field path string # Path relative to the vault where file should be created
---@field templateName string # Name of the template to use
---@field templateVariables table<string, string> # Map of Template variables to substitue

-- Note creator
---@param noteOptions NoteOptions
---@return string|nil fileName # File name of created note
function NoteAPI.createNoteFromTemplate(noteOptions)
	-- Verify template existence
	local util = require("obsidian.util")
	local cfg = require("obsidian").get_config()
	local templatePath = cfg.obsidian_vault_dir .. cfg.template_dir .. noteOptions.templateName
	if not util.check_file_exists(templatePath) then
		vim.notify("Template " .. templatePath .. " does not exist", vim.log.levels.ERROR)
		return nil
	end

	local err = util.copy_file_and_rename(templatePath, noteOptions.path, noteOptions.fileName)
	if err ~= nil then
		vim.notify("Could not create with template" .. templatePath .. " Err: " .. err, vim.log.levels.ERROR)
		return nil
	end

	-- For every templated variable we have we now replace the associated instance of {{ var-name }} in our note
	local replaceErr =
		util.find_and_replace(noteOptions.path .. "/" .. noteOptions.fileName, noteOptions.templateVariables)

	if err ~= nil then
		vim.notify("Could not substitute template vars Err: " .. replaceErr, vim.log.levels.ERROR)
		return nil
	end
end

return NoteAPI
