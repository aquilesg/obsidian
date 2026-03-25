--- Backward-compatible entry: same module as **`obsidian.cmp.tags_body`** (body-only `#` tags).
---
--- Prefer registering two providers explicitly:
--- - `obsidian.cmp.tags_body` — note body
--- - `obsidian.cmp.tags_frontmatter` — YAML frontmatter
---
--- @module 'obsidian.cmp'

return require("obsidian.cmp.tags_body")
