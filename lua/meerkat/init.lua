local load_config = require("meerkat.loader")
local runner = require("meerkat.runner")
local input = require("meerkat.input")
local ui = require("meerkat.ui")
local config = require("meerkat.config")

local M = {}

--- Configure Meerkat. Example:
---
---   require("meerkat").setup({
---     sources = {
---       { name = "Personal", path = vim.fn.stdpath("config") .. "/workflows" },
---       { name = "LAN", path = "//shared-nas/devops/workflows" },
---     },
---     default_source = "Personal",
---   })
function M.setup(opts)
  config.setup(opts)
end

--- Prompts for a workflow's inputs, then executes its steps.
local function run_workflow(workflow)
  input.collect(workflow, function(values)
    runner.run_workflow(workflow, values)
  end)
end

--- Prompts for a workflow's inputs, then shows the expanded pipeline.
local function dry_run_workflow(workflow)
  input.collect(workflow, function(values)
    runner.dry_run(workflow, values)
  end)
end

--- Opens the Meerkat interactive picker.
function M.open()
  local data = load_config()

  if not data or not data.commands or #data.commands == 0 then
    vim.notify("No Meerkat workflows found.", vim.log.levels.WARN)
    return
  end

  ui.open(data.commands, run_workflow, dry_run_workflow, {
    sources = data.sources,
    default_source = config.get().default_source,
  })
end

vim.api.nvim_create_user_command("Meerkat", M.open, {
  desc = "Open the Meerkat workflow picker",
})

--- Prints the picker's floating windows (mainly for debugging).
vim.api.nvim_create_user_command("MeerkatDebug", function()
  print(string.format("screen lines=%d cols=%d", vim.o.lines, vim.o.columns))
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(w)
    local buf = vim.api.nvim_win_get_buf(w)
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""

    local title = ""
    if cfg.title and cfg.title[1] and cfg.title[1][1] then
      title = cfg.title[1][1]
    end

    print(string.format(
      "win=%d title=%q line=%q row=%s col=%s w=%s h=%s",
      w, title, line,
      tostring(vim.inspect(cfg.row)), tostring(vim.inspect(cfg.col)),
      tostring(vim.inspect(cfg.width)), tostring(vim.inspect(cfg.height))
    ))
  end
end, {
  desc = "Debug Meerkat picker windows",
})

vim.cmd(
  "cnoreabbrev <expr> meerkat getcmdtype() == ':' && getcmdline() ==# 'meerkat' ? 'Meerkat' : 'meerkat'"
)

return M