--- Blink.cmp source: tag completion inside **YAML frontmatter** only (between `---` fences).
---
--- - **`#tag`** — same as the body source (replaces from `#` through the cursor).
--- - **Bare tags** on lines matching `^\s*-\s` (list items) or `^\s*tags:\s` — uses blink’s
---   keyword range and inserts the tag **without** a leading `#` (YAML-friendly).
---
--- ```lua
--- obsidian_tags_frontmatter = {
---   name = 'Obsidian (FM)',
---   module = 'obsidian.cmp.tags_frontmatter',
---   opts = {},
--- },
--- ```
---
--- @module 'obsidian.cmp.tags_frontmatter'

local shared = require("obsidian.cmp.tags_shared")

return {
	new = function(opts, provider)
		return shared.new("frontmatter", opts, provider)
	end,
}
