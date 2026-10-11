local meerkat_config = require("meerkat.config")

local function get_plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h")
end

--- Splits a workflow's path (relative to its source root) into a category and
--- an optional nested subcategory.
local function parse_location(relative_path)
  local category, subcategory =
    relative_path:match("^([^/\\]+)[/\\](.*)[/\\][^/\\]+$")

  if not category then
    category = relative_path:match("^([^/\\]+)[/\\]")
  end

  if subcategory then
    subcategory = subcategory:gsub("[/\\][^/\\]+$", "")
  end

  return category, subcategory
end

--- Returns the ordered list of sources to load, with `~` and `$VAR` expanded
--- in each path.
local function resolve_sources()
  local configured = meerkat_config.get().sources
  local raw = {}

  if configured and #configured > 0 then
    raw = configured
  else
    table.insert(raw, {
      name = "Built-in",
      path = get_plugin_root() .. "/workflows",
    })

    local personal = vim.fn.stdpath("config") .. "/workflows"

    if personal ~= raw[1].path then
      table.insert(raw, { name = "Personal", path = personal })
    end
  end

  local sources = {}

  for _, source in ipairs(raw) do
    if source.path and source.path ~= "" then
      table.insert(sources, {
        name = source.name or "Unnamed",
        path = vim.fn.expand(source.path),
      })
    end
  end

  return sources
end

--- Loads every workflow from a single source into `config.commands`.
--- Returns true when the source directory exists (even if it is empty).
local function load_source(source, config)
  local path = source.path

  if vim.fn.isdirectory(path) ~= 1 then
    return false
  end

  local files = vim.fn.globpath(path, "**/*.json", false, true)

  for _, file_path in ipairs(files) do
    local file = io.open(file_path, "r")

    if file then
      local content = file:read("*a")
      file:close()

      local ok, workflow = pcall(vim.json.decode, content)

      if ok and type(workflow) == "table" then
        local relative_path = file_path:sub(#path + 2)
        local category, subcategory = parse_location(relative_path)

        workflow.category = category
        workflow.subcategory = subcategory
        workflow.source = source.name
        workflow.source_path = file_path
        workflow.file_dir = vim.fn.fnamemodify(file_path, ":h")

        workflow.name = workflow.name
          or vim.fn.fnamemodify(file_path, ":t:r")

        table.insert(config.commands, workflow)
      else
        vim.notify(
          "Invalid workflow JSON: " .. file_path,
          vim.log.levels.ERROR
        )
      end
    end
  end

  return true
end

--- Loads every workflow from every available source.
--- Returns `{ commands = {...}, sources = { { name, path }, ... } }`.
local function load_config()
  local config = { commands = {}, sources = {} }

  for _, source in ipairs(resolve_sources()) do
    if load_source(source, config) then
      table.insert(config.sources, { name = source.name, path = source.path })
    end
  end

  table.sort(config.commands, function(a, b)
    if a.category ~= b.category then
      return (a.category or "") < (b.category or "")
    end

    return a.name < b.name
  end)

  return config
end

return load_config
