local Note = require("obsidian.note")
local obsidian = require("obsidian")

describe("Note.createNoteFromTemplate", function()
	local test_vault_dir = "/tmp/obsidian_test_vault"

	before_each(function()
		obsidian.setup({
			obsidian_vault_dir = test_vault_dir,
			template_dir = "templates",
		})
		if vim.fn.isdirectory(test_vault_dir) == 1 then
			vim.fn.delete(test_vault_dir, "rf")
		end
		vim.fn.mkdir(test_vault_dir .. "/templates", "p")
	end)

	after_each(function()
		if vim.fn.isdirectory(test_vault_dir) == 1 then
			vim.fn.delete(test_vault_dir, "rf")
		end
	end)

	it("copies a template into the vault and substitutes variables", function()
		local tpl = test_vault_dir .. "/templates/task.md"
		local f = assert(io.open(tpl, "w"))
		f:write("# {{ title }}\n{{ title }}\n")
		f:close()

		Note.createNoteFromTemplate({
			templateName = "task.md",
			path = "projects",
			fileName = "new-task.md",
			templateVariables = { title = "My Task" },
		})

		local out = test_vault_dir .. "/projects/new-task.md"
		assert.is_true(vim.fn.filereadable(out) == 1)
		local rf = assert(io.open(out, "r"))
		local content = rf:read("*a")
		rf:close()
		assert.equals("# My Task\nMy Task\n", content)
	end)

	it("merges optional frontmatter when the template has no YAML block", function()
		local tpl = test_vault_dir .. "/templates/plain.md"
		local f = assert(io.open(tpl, "w"))
		f:write("# Title\n")
		f:close()

		Note.createNoteFromTemplate({
			templateName = "plain.md",
			path = "",
			fileName = "out.md",
			templateVariables = {},
			frontmatter = {
				status = "draft",
				tags = { "a", "b" },
			},
		})

		local out = test_vault_dir .. "/out.md"
		local rf = assert(io.open(out, "r"))
		local content = rf:read("*a")
		rf:close()
		assert.matches("status: draft", content)
		assert.matches("tags:", content)
		assert.matches("# Title", content)
	end)

	it("merges optional frontmatter when the template already has YAML", function()
		local tpl = test_vault_dir .. "/templates/withfm.md"
		local f = assert(io.open(tpl, "w"))
		f:write("---\nkind: task\n---\n\nBody.\n")
		f:close()

		Note.createNoteFromTemplate({
			templateName = "withfm.md",
			path = "",
			fileName = "merged.md",
			templateVariables = {},
			frontmatter = { status = "done" },
		})

		local out = test_vault_dir .. "/merged.md"
		local rf = assert(io.open(out, "r"))
		local content = rf:read("*a")
		rf:close()
		assert.matches("kind: task", content)
		assert.matches("status: done", content)
		assert.matches("Body.", content)
	end)

	it("returns nil when the template file is missing", function()
		local result = Note.createNoteFromTemplate({
			templateName = "missing.md",
			path = "",
			fileName = "x.md",
			templateVariables = {},
		})
		assert.is_nil(result)
	end)
end)
