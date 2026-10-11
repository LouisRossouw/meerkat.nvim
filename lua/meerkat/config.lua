local M = {}

local defaults = {
  -- List of named workflow sources, e.g.
  --   { { name = "Personal", path = "~/workflows" },
  --     { name = "LAN", path = "Z:/devops/workflows" } }
  -- When nil, Meerkat falls back to the built-in workflows plus
  -- `stdpath("config")/workflows`.
  sources = nil,

  -- Source selected when the picker opens. May be a source name or "All".
  -- When nil, the first available source is used.
  default_source = nil,
}

local current = vim.deepcopy(defaults)

--- Applies user configuration. Safe to call multiple times.
function M.setup(opts)
  opts = opts or {}
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
end

--- Returns the active configuration table.
function M.get()
  return current
end

--- Restores the default configuration (mainly useful for tests).
function M.reset()
  current = vim.deepcopy(defaults)
end

return M
