# obsidian.nvim

A minimal Neovim plugin for working with Obsidian notes.

## Installation

```lua
use {
  "aquilesgomez/obsidian",
  config = function()
    require("obsidian").setup({
      obsidian_vault_dir = "~/Documents/ObsidianVault",
    })
  end
}
```

## Road Map

This plug is designed entirely to allow access to your Obsidian Vault,
but does not contain anything beyond that.
This plugin is intended to be used via API call and does not support features such as:

`Obsidian CreateNote`

- [>] Note Creation
  - [ ] Template Substitution
- [ ] Note Searching
- [ ] Note Renaming
- [ ] Tag Creation
- [ ] Tag Searching
- Completion
  - [ ] Notes Based off of Name
- [ ] Tags Based off of Name

### Underlying Process

On init and whenever a new tag / note is created; this plugin
indexes each entry to correlate tags to a respective note.

This allows for quick searching within your vault.

## Testing

This plugin uses [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for testing.

To run tests:

```bash
nvim --headless -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/init.lua' }"
```

Or using the plenary test runner:

```lua
:lua require('plenary.test_harness').test_directory('tests')
```
