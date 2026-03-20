local Note = require("obsidian.note")
local obsidian = require("obsidian")

describe("Note.create", function()
	local test_vault_dir = "/tmp/obsidian_test_vault"
	
	before_each(function()
		-- Setup test vault directory
		obsidian.setup({
			obsidian_vault_dir = test_vault_dir,
		})
		
		-- Clean up test directory before each test
		if vim.fn.isdirectory(test_vault_dir) == 1 then
			vim.fn.delete(test_vault_dir, "rf")
		end
	end)
	
	after_each(function()
		-- Clean up test directory after each test
		if vim.fn.isdirectory(test_vault_dir) == 1 then
			vim.fn.delete(test_vault_dir, "rf")
		end
	end)
	
	it("should create a note file with just an ID", function()
		Note.create({
			id = "TestNote",
		})
		
		local note_path = test_vault_dir .. "/TestNote.md"
		assert.is_true(vim.fn.filereadable(note_path) == 1, "Note file should be created")
		
		-- Check file is empty (no frontmatter)
		local file = io.open(note_path, "r")
		local content = file:read("*all")
		file:close()
		assert.equals("", content, "Note should be empty when no frontmatter provided")
	end)
	
	it("should create a note with frontmatter containing simple values", function()
		Note.create({
			id = "TestNoteWithFrontmatter",
			frontmatter = {
				creation_date = "2026-01-05",
				document_type = "task",
				status = "In Progress",
			},
		})
		
		local note_path = test_vault_dir .. "/TestNoteWithFrontmatter.md"
		assert.is_true(vim.fn.filereadable(note_path) == 1, "Note file should be created")
		
		local file = io.open(note_path, "r")
		local content = file:read("*all")
		file:close()
		
		assert.matches("creation_date: 2026%-01%-05", content, "Should contain creation_date")
		assert.matches("document_type: task", content, "Should contain document_type")
		assert.matches("status: In Progress", content, "Should contain status")
		assert.matches("^---", content, "Should start with frontmatter delimiter")
		assert.matches("---$", content:match("---\n.*\n(---)"), "Should end with frontmatter delimiter")
	end)
	
	it("should create a note with frontmatter containing arrays", function()
		Note.create({
			id = "TestNoteWithArrays",
			frontmatter = {
				tags = {
					"Work/IH/tools/aws/MSK",
					"Work/IH/task",
					"Work/IH/write-up/kafka",
				},
				aliases = {
					"CLOUD-6755",
				},
			},
		})
		
		local note_path = test_vault_dir .. "/TestNoteWithArrays.md"
		assert.is_true(vim.fn.filereadable(note_path) == 1, "Note file should be created")
		
		local file = io.open(note_path, "r")
		local content = file:read("*all")
		file:close()
		
		assert.matches("tags:", content, "Should contain tags key")
		assert.matches("    %- Work/IH/tools/aws/MSK", content, "Should contain first tag with 4-space indentation")
		assert.matches("    %- Work/IH/task", content, "Should contain second tag")
		assert.matches("    %- Work/IH/write-up/kafka", content, "Should contain third tag")
		assert.matches("aliases:", content, "Should contain aliases key")
		assert.matches("    %- CLOUD%-6755", content, "Should contain alias with 4-space indentation")
	end)
	
	it("should create a note with complex frontmatter matching the example", function()
		Note.create({
			id = "ScaleKafkaToRightSize",
			frontmatter = {
				creation_date = "2026-01-05",
				document_type = "task",
				id = "ScaleKafkaToRightSize",
				domain = {
					"resiliancy",
					"data",
				},
				work_type = {
					"tech_debt",
				},
				status = "In Progress",
				tags = {
					"Work/IH/tools/aws/MSK",
					"Work/IH/task",
					"Work/IH/write-up/kafka",
				},
				aliases = {
					"CLOUD-6755",
				},
			},
		})
		
		local note_path = test_vault_dir .. "/ScaleKafkaToRightSize.md"
		assert.is_true(vim.fn.filereadable(note_path) == 1, "Note file should be created")
		
		local file = io.open(note_path, "r")
		local content = file:read("*all")
		file:close()
		
		-- Verify all expected fields are present
		assert.matches("creation_date: 2026%-01%-05", content)
		assert.matches("document_type: task", content)
		assert.matches("id: ScaleKafkaToRightSize", content)
		assert.matches("status: In Progress", content)
		
		-- Verify arrays with proper indentation
		assert.matches("domain:", content)
		assert.matches("    %- resiliancy", content)
		assert.matches("    %- data", content)
		
		assert.matches("work_type:", content)
		assert.matches("    %- tech_debt", content)
		
		assert.matches("tags:", content)
		assert.matches("    %- Work/IH/tools/aws/MSK", content)
		assert.matches("    %- Work/IH/task", content)
		assert.matches("    %- Work/IH/write-up/kafka", content)
		
		assert.matches("aliases:", content)
		assert.matches("    %- CLOUD%-6755", content)
		
		-- Verify frontmatter delimiters
		assert.matches("^---", content)
		assert.matches("\n---\n\n$", content, "Should end with frontmatter delimiter and two newlines")
	end)
	
	it("should create note in subdirectory when path is provided", function()
		Note.create({
			id = "SubdirNote",
			path = "notes/subfolder",
		})
		
		local note_path = test_vault_dir .. "/notes/subfolder/SubdirNote.md"
		assert.is_true(vim.fn.filereadable(note_path) == 1, "Note file should be created in subdirectory")
	end)
	
	it("should error when note already exists", function()
		-- Create the note first
		Note.create({
			id = "ExistingNote",
		})
		
		-- Try to create it again
		assert.has_error(function()
			Note.create({
				id = "ExistingNote",
			})
		end, "Note with ID 'ExistingNote' already exists")
	end)
	
	it("should error when obsidian_vault_dir is not configured", function()
		obsidian.setup({})
		
		assert.has_error(function()
			Note.create({
				id = "TestNote",
			})
		end, "obsidian_vault_dir not configured")
	end)
	
	it("should create directory structure if it doesn't exist", function()
		Note.create({
			id = "DeepNote",
			path = "very/deep/nested/path",
		})
		
		local note_path = test_vault_dir .. "/very/deep/nested/path/DeepNote.md"
		assert.is_true(vim.fn.filereadable(note_path) == 1, "Note should be created in nested directory")
		assert.is_true(vim.fn.isdirectory(test_vault_dir .. "/very/deep/nested/path") == 1, "Directory structure should be created")
	end)
	
	it("should handle empty frontmatter gracefully", function()
		Note.create({
			id = "EmptyFrontmatterNote",
			frontmatter = {},
		})
		
		local note_path = test_vault_dir .. "/EmptyFrontmatterNote.md"
		assert.is_true(vim.fn.filereadable(note_path) == 1, "Note file should be created")
		
		local file = io.open(note_path, "r")
		local content = file:read("*all")
		file:close()
		
		assert.equals("", content, "Note should be empty when frontmatter is empty table")
	end)
end)


