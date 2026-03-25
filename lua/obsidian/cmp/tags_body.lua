--- Blink.cmp source: `#` tag completion in the markdown **body** (outside YAML frontmatter).
---
--- Register alongside `obsidian.cmp.tags_frontmatter` if you want tags in both places.
---
--- ```lua
--- obsidian_tags_body = {
---   name = 'Obsidian (body)',
---   module = 'obsidian.cmp.tags_body',
---   opts = {},
--- },
--- ```
---
--- @module 'obsidian.cmp.tags_body'

local shared = require("obsidian.cmp.tags_shared")

return {
	new = function(opts, provider)
		return shared.new("body", opts, provider)
	end,
}
