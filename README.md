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
- [x] Pomodoro control (TaskNotes)
- Completion
  - [ ] Notes Based off of Name
  - [x] Tags Based off of Name

## Pomodoro

Controls the TaskNotes pomodoro of the vault through the Obsidian CLI. Call `setup()` eagerly --
somewhere that runs at startup, such as your statusline config -- so the background poll keeps the
cached session state fresh:

```lua
require("obsidian.pomodoro").setup({
  vault = "brain",      -- CLI `vault=` name; defaults to the basename of `obsidian_vault_dir`
  poll_ms = 15000,      -- how often to resync with the CLI
  keymaps = true,       -- register `<leader>op{s,e,p,r,i}`
  keymap_prefix = "<leader>op",
})
```

`:Pomodoro [start|stop|pause|resume|status]` runs an action and reports the result;
`start` uses an open vault note as the TaskNotes task (prompting when several are open).

For a statusline component, `require("obsidian.pomodoro").statusline()` returns the remaining
minutes and session type (empty when no session is active), and `cache.status` is
`"running" | "paused" | "stopped"`:

```lua
{
  function()
    return require("obsidian.pomodoro").statusline()
  end,
  cond = function()
    return require("obsidian.pomodoro").cache.status ~= "stopped"
  end,
}
```

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
