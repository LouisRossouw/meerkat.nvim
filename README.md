# meerkat.nvim

A lightweight, JSON-driven workflow runner for Neovim with built-in live fuzzy search and category browsing.

Requires Neovim **0.12 or newer** (for `vim.pack`). There are no external dependencies.

---

## Installation

Add the plugin with `vim.pack` in your `init.lua`, then call `setup()`:

```lua
vim.pack.add { "https://github.com/LouisRossouw/meerkat.nvim" }

require("meerkat").setup {
  sources = {
    { name = "Personal", path = vim.fn.stdpath("config") .. "/workflows" },
    -- e.g. { name = "Shared", path = "Z:/workflows" },
  },
  default_source = "Personal",
}
```

## Usage

Run `:Meerkat` (or `:meerkat`) to open the floating picker.

- **Search:** Start typing to live fuzzy-search across all workflows.
- **Run:** Press `<CR>` on any highlighted workflow.
- **Dry Run:** Press `<C-d>` on any workflow to inspect its expanded commands before executing.
- **Open Folder:** Press `<C-o>` on a workflow or folder to reveal it in your OS file manager (Explorer / Finder / `xdg-open`).
- **Sources:** Press `<C-s>` / `<M-s>` to cycle between workflow sources (see [Configuration](#configuration)).


## Workflow File Format

Workflows are `.json` files placed in the `workflows/` directory. Subdirectories automatically become categories and folders:


workflows/
├── Hosts/
│ └── connect.json
└── Deploy/
└── deploy-api.json


See the workflows/examples/

---

## Supported Step Types

- `confirm`: Prompt yes/no confirmation (`message`)
- `notify`: Show a Neovim notification (`message`)
- `sleep`: Pause execution (`seconds`)
- `local_command`: Run detached local command (`command: ["cmd", "arg"]`)
- `ssh_terminal`: Open interactive SSH terminal tab (`host`)
- `ssh_command`: Run SSH command in a terminal (`host`, `command`)
- `vim_command`: Execute a Vim command (`command`)
- `lua_command`: Execute a Lua code snippet (`code`)
- `clipboard`: Copy text to system clipboard (`text`)
- `open_url`: Open URL in default browser (`url`)
- `http_request`: Send async HTTP request via curl (`url`, `method`, `body`, `headers`, `save_to`). If `save_to` is provided, responses are saved into workflow variables for subsequent steps (e.g. `{my_var}` or `{my_var.field}` for JSON).

---

## License

Distributed under the [MIT License](LICENSE).
```
