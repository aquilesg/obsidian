local util = require("obsidian.util")

describe("obsidian.util", function()
	local tmp = "/tmp/obsidian_util_test"

	before_each(function()
		if vim.fn.isdirectory(tmp) == 1 then
			vim.fn.delete(tmp, "rf")
		end
		vim.fn.mkdir(tmp, "p")
	end)

	after_each(function()
		if vim.fn.isdirectory(tmp) == 1 then
			vim.fn.delete(tmp, "rf")
		end
	end)

	describe("fileRelativeToVault", function()
		it("returns a vault-relative path with forward slashes", function()
			local vault = vim.fs.normalize(tmp .. "/vault")
			local file = vim.fs.normalize(vault .. "/projects/a.md")
			assert.are.same("projects/a.md", util.fileRelativeToVault(vault, file))
		end)

		it("returns nil when the file is outside the vault", function()
			local vault = vim.fs.normalize(tmp .. "/vault")
			local outside = vim.fs.normalize(tmp .. "/other/x.md")
			assert.is_nil(util.fileRelativeToVault(vault, outside))
		end)
	end)

	describe("checkFileExists", function()
		it("returns true for an existing file", function()
			local p = tmp .. "/exists.txt"
			local f = assert(io.open(p, "w"))
			f:write("x")
			f:close()
			assert.is_true(util.checkFileExists(p))
		end)

		it("returns false when path is missing", function()
			assert.is_false(util.checkFileExists(tmp .. "/nope.txt"))
		end)

		it("returns false for a directory path", function()
			assert.is_false(util.checkFileExists(tmp))
		end)
	end)

	describe("copyFileAndRename", function()
		it("copies file contents to a new name in destination", function()
			local src = tmp .. "/source.md"
			local f = assert(io.open(src, "w"))
			f:write("hello")
			f:close()

			local dest = tmp .. "/out"
			vim.fn.mkdir(dest, "p")
			assert.is_nil(util.copyFileAndRename(src, dest, "copy.md"))

			local out = dest .. "/copy.md"
			assert.is_true(vim.fn.filereadable(out) == 1)
			local rf = assert(io.open(out, "r"))
			assert.equals("hello", rf:read("*a"))
			rf:close()
		end)

		it("appends slash to destination when missing", function()
			local src = tmp .. "/a.txt"
			local wf = assert(io.open(src, "w"))
			wf:write("z")
			wf:close()
			local dest = tmp .. "/d"
			vim.fn.mkdir(dest, "p")
			assert.is_nil(util.copyFileAndRename(src, dest .. "/", "b.txt"))
			local rf = assert(io.open(dest .. "/b.txt", "r"))
			assert.equals("z", rf:read("*a"))
			rf:close()
		end)

		it("returns an error when source cannot be read", function()
			local err = util.copyFileAndRename(tmp .. "/missing", tmp, "x.md")
			assert.is_string(err)
			assert.matches("Failed to open source", err)
		end)
	end)

	describe("findAndReplace", function()
		it("substitutes {{ key }} placeholders", function()
			local p = tmp .. "/tpl.md"
			local f = assert(io.open(p, "w"))
			f:write("Title: {{ title }}\nBody {{ title }} end")
			f:close()

			assert.is_nil(util.findAndReplace(p, { title = "MyNote" }))
			local rf = assert(io.open(p, "r"))
			local content = rf:read("*a")
			rf:close()
			assert.equals("Title: MyNote\nBody MyNote end", content)
		end)

		it("allows flexible whitespace inside braces", function()
			local p = tmp .. "/ws.md"
			local wf = assert(io.open(p, "w"))
			wf:write("{{  spaced  }}")
			wf:close()
			assert.is_nil(util.findAndReplace(p, { spaced = "ok" }))
			local rf = assert(io.open(p, "r"))
			assert.equals("ok", rf:read("*a"))
			rf:close()
		end)

		it("returns nil for empty vars table", function()
			local p = tmp .. "/noop.md"
			local wf = assert(io.open(p, "w"))
			wf:write("unchanged")
			wf:close()
			assert.is_nil(util.findAndReplace(p, {}))
			local rf = assert(io.open(p, "r"))
			assert.equals("unchanged", rf:read("*a"))
			rf:close()
		end)
	end)

	describe("front matter helpers", function()
		it("splitNoteContent returns nil when there is no front matter", function()
			local y, b = util.splitNoteContent("# Hello\n")
			assert.is_nil(y)
			assert.equals("# Hello\n", b)
		end)

		it("splitNoteContent parses scalars and body", function()
			local note = "---\nstatus: todo\ntitle: A\n---\n\nbody here\n"
			local y, b = util.splitNoteContent(note)
			assert.equals("status: todo\ntitle: A", y)
			assert.equals("body here\n", b)
		end)

		it("splitNoteContent handles empty YAML between delimiters", function()
			local note = "---\n---\n\nbody only\n"
			local y, b = util.splitNoteContent(note)
			assert.equals("", y)
			assert.equals("body only\n", b)
		end)

		it("parseYamlFrontmatterBlock reads scalars and lists", function()
			local yaml = "status: In Progress\ntags:\n  - a\n  - b\n"
			local data, order, err = util.parseYamlFrontmatterBlock(yaml)
			assert.is_nil(err)
			assert.equals("In Progress", data.status)
			assert.same({ "a", "b" }, data.tags)
			assert.is_not_nil(order)
			assert.is_not_nil(data.status)
			assert.is_not_nil(data.tags)
		end)

		it("serializeFrontmatter round-trips with split", function()
			local inner = "status: done\n"
			local out = util.serializeFrontmatter({ status = "done" }, { "status" })
			assert.equals("status: done\n", out)
			local full = util.buildNoteWithFrontmatter(out, "hello")
			local y, b = util.splitNoteContent(full)
			assert.equals("status: done", y)
			assert.equals("hello", b)
		end)
	end)
end)
