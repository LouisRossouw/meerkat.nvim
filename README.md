# meerkat.nvim

A lightweight, JSON-driven workflow runner for Neovim with built-in live fuzzy search and category browsing.

_Die meerkatte loop die workflows!_

Requires Neovim **0.9 or newer** — there are no external dependencies. (The built-in `vim.pack` install path below needs 0.12+.)

---

## Installation

### Option 1 — Plugin manager (recommended)

**lazy.nvim** — add to your plugin spec, or call `setup()` from the `config` function:

```lua
{
  "LouisRossouw/meerkat.nvim",
  config = function()
    require("meerkat").setup {
      sources = {
        { name = "Personal", path = vim.fn.stdpath("config") .. "/workflows" },
      },
      default_source = "Personal",
    }
  end,
}
```

**vim.pack** — built into Neovim 0.12+. Add it anywhere in `init.lua`:

```lua
vim.pack.add { "https://github.com/LouisRossouw/meerkat.nvim" }

require("meerkat").setup {
  sources = {
    { name = "Personal", path = vim.fn.stdpath("config") .. "/workflows" },
  },
  default_source = "Personal",
}
```

**Other managers:**

- **packer.nvim** — `use "LouisRossouw/meerkat.nvim"` (or `use { "LouisRossouw/meerkat.nvim", config = function() ... end }`), then call `require("meerkat").setup { ... }` yourself.
- **vim-plug** — `Plug 'LouisRossouw/meerkat.nvim'` in `init.vim`, run `:PlugInstall`, then add the `setup()` call in `init.lua`/`init.vim`.

### Option 2 — No plugin manager (manual clone)

Neovim automatically loads any plugin placed in a `pack/*/start/` directory on your
**packpath** (`:help packpath`) — no config needed. Clone the repo there:

**Linux / macOS:**

```bash
git clone https://github.com/LouisRossouw/meerkat.nvim.git ~/.local/share/nvim/site/pack/plugins/start/meerkat.nvim
```

**Windows (cmd):**

```bat
git clone https://github.com/LouisRossouw/meerkat.nvim.git "%LOCALAPPDATA%\nvim-data\site\pack\plugins\start\meerkat.nvim"
```

To update, run `git pull` inside the cloned folder (or use your plugin manager's update command).

> **Prefer keeping plugins inside your config?** Any `pack/*/start/` folder on your packpath works — e.g. `~/.config/nvim/pack/plugins/start/meerkat.nvim` on Linux/macOS, or `%LOCALAPPDATA%\nvim\pack\plugins\start\meerkat.nvim` on Windows.

### After installing

Call `setup()` from your `init.lua` (either standalone or in your plugin manager's `config` block):

```lua
require("meerkat").setup {
  sources = {
    { name = "Personal", path = vim.fn.stdpath("config") .. "/workflows" },
    -- e.g. { name = "LAN", path = "//shared-nas/devops/workflows" },
  },
  default_source = "Personal",
}
```

Then run `:Meerkat` to open the picker. Each `sources` entry points at a folder of
`.json` workflow files (subdirectories become categories — see
[Workflow File Format](#workflow-file-format)). If `sources` is omitted, Meerkat falls
back to the built-in `<install-root>/workflows/` folder plus
`stdpath("config")/workflows`.

---

## Usage

Run `:Meerkat` (or `:meerkat`) to open the floating picker.

- **Search:** Start typing to live fuzzy-search across all workflows.
- **Run:** Press `<CR>` on any highlighted workflow.
- **Dry Run:** Press `<C-d>` on any workflow to inspect its expanded commands before executing.
- **Open Folder:** Press `<C-o>` on a workflow or folder to reveal it in your OS file manager (Explorer / Finder / `xdg-open`).
- **Sources:** Press `<C-s>` / `<M-s>` to cycle between workflow sources (see [Configuration](#configuration)).

---

## Configuration

Meerkat works with zero configuration, but you can point it at multiple named
workflow sources — for example a personal folder alongside a team share on the
LAN. Call `setup()` from your `init.lua`:

```lua
require("meerkat").setup({
  sources = {
    { name = "Personal", path = vim.fn.stdpath("config") .. "/workflows" },
    { name = "LAN", path = "/some-network-path/workflows" }
  },
  -- Source shown when the picker opens. Use a source name or "All".
  default_source = "Personal",
})
```

When multiple sources are available the results window title shows the active
source (e.g. `Meerkat [LAN]`), a **source indicator** sits below the list showing
each source's initial (e.g. `P  •  L  •  A`) with the active one highlighted in
orange, and `All` merges every source together. Live search results are labelled
with their source, e.g. `[LAN • Deploy] Deploy API`.

If `setup()` is never called, Meerkat defaults to the built-in `workflows/`
directory plus `stdpath("config")/workflows`. Sources whose directory does not
exist (for example an unmounted network share) are skipped automatically.

---

## Keybindings (Inside `:Meerkat`)

| Context                   | Key                 | Action                                           |
| ------------------------- | ------------------- | ------------------------------------------------ |
| **Search (Insert Mode)**  | _Any text_          | Real-time fuzzy filter                           |
|                           | `<Down>` / `<C-n>`  | Move selection down                              |
|                           | `<Up>` / `<C-p>`    | Move selection up                                |
|                           | `<CR>`              | Execute workflow / Enter folder                  |
|                           | `<C-d>`             | **Dry run** (preview steps)                      |
|                           | `<C-o>`             | Open selected folder/workflow in file manager    |
|                           | `<C-s>` / `<M-s>`   | Cycle workflow source                            |
|                           | `<Tab>` / `<S-Tab>` | Cycle category tabs (when search is empty)       |
|                           | `<BS>`              | Go back a directory level (when search is empty) |
|                           | `<Esc>`             | Switch to Normal mode                            |
|                           | `<C-c>`             | Close picker                                     |
| **Results (Normal Mode)** | `j` / `k`           | Move cursor up / down                            |
|                           | `h` / `l` / `<Tab>` | Cycle category tabs                              |
|                           | `<C-s>` / `<M-s>`   | Cycle workflow source                            |
|                           | `<CR>`              | Execute workflow / Enter folder                  |
|                           | `<C-d>`             | **Dry run**                                      |
|                           | `<C-o>`             | Open selected folder/workflow in file manager    |
|                           | `u` / `<BS>`        | Go back a directory level                        |
|                           | `i` / `a` / `/`     | Jump back into search bar                        |
|                           | `q` / `<Esc>`       | Close picker                                     |

---

## Workflow File Format

Workflows are `.json` files placed in the `workflows/` directory. Subdirectories automatically become categories and folders:

```
workflows/
├── Hosts/
│   └── connect.json
└── Deploy/
    └── deploy-api.json
```

### Example Workflow

```json
{
  "name": "Deploy API",
  "description": "Deploy to chosen environment",
  "inputs": [
    {
      "name": "env",
      "prompt": "Environment",
      "type": "select",
      "choices": ["staging", "production"]
    },
    {
      "name": "host",
      "prompt": "Server Host",
      "default": "$DEFAULT_HOST"
    }
  ],
  "steps": [
    {
      "type": "confirm",
      "message": "Deploy to {env} on {host}?"
    },
    {
      "type": "ssh_command",
      "host": "{host}",
      "command": "systemctl restart api"
    },
    {
      "type": "notify",
      "message": "Successfully deployed to {env}!"
    }
  ]
}
```

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
