-- Note API

local NoteAPI = {}

---@class NoteOptions
---@field fileName string # Filename for the note
---@field path string # Path relative to the vault where file should be created
---@field templateName string # Name of the template to use
---@field templateVariables table<string, string> # Map of Template variables to substitue

-- Note creator
---@param noteOptions NoteOptions
---@return string fileName # File name of created note
function NoteAPI.createNote(noteOptions)
	-- Create a note first from the template
	local createNoteCmd = "obsidian create name="
		.. noteOptions.fileName
		.. " path="
		.. noteOptions.path
		.. " template="
		.. noteOptions.templateName

	return noteOptions.fileName
end
