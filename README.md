# Obsidian

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

- [x] Note Creation
  - [x] Template Substitution
- [x] Note Searching
- [x] Note Renaming
- [x] Tag Creation
- [x] Tag Searching
- Completion
  - [ ] Notes Based off of Name
  - [x] Tags Based off of Name

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
