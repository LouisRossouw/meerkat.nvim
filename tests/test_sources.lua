-- Tests for multi-source configuration (setup({ sources = {...} })).
local meerkat = require("meerkat")
local config = require("meerkat.config")

local function write_file(path, contents)
  local file = assert(io.open(path, "w"))
  file:write(contents)
  file:close()
end

local function make_source(name, category, workflow_name)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/" .. category, "p")
  write_file(
    dir .. "/" .. category .. "/" .. workflow_name .. ".json",
    vim.json.encode({
      name = workflow_name,
      description = workflow_name .. " description",
      steps = {},
    })
  )
  return { name = name, path = dir }
end

local alpha = make_source("Alpha", "CatA", "Alpha One")
local beta = make_source("Beta", "CatB", "Beta Two")

config.setup({
  sources = { alpha, beta },
  default_source = "Alpha",
})

meerkat.open()

-- Locate the floating windows: results, prompt, and the untitled footer.
local results_win, results_buf, prompt_buf, footer_buf
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local cfg = vim.api.nvim_win_get_config(w)
  local title = cfg.title and cfg.title[1] and cfg.title[1][1]
  local buf = vim.api.nvim_win_get_buf(w)

  if title and title:find("Meerkat") then
    results_win = w
    results_buf = buf
  elseif title and title:find("Search") then
    prompt_buf = buf
  elseif not title then
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    if line:find("•", 1, true) then
      footer_buf = buf
    end
  end
end

assert(results_win and prompt_buf, "Picker windows should exist")
assert(footer_buf, "Source indicator footer should exist")

local function title()
  return vim.api.nvim_win_get_config(results_win).title[1][1]
end

local function footer_text()
  return vim.api.nvim_buf_get_lines(footer_buf, 0, 1, false)[1] or ""
end

--- Returns the column(s) highlighted with the active-source group.
local function active_cols()
  local cols = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(footer_buf, -1, 0, -1, { details = true })) do
    if m[4] and m[4].hl_group == "MeerkatSourceActive" then
      table.insert(cols, m[3])
    end
  end
  return cols
end

local function send(keys)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(keys, true, false, true),
    "m",
    false
  )
end

assert(title():find("%[Alpha%]"), "Initial source should be Alpha, got: " .. title())
print("PASS: default_source = Alpha")

-- Footer should list A • B • A (Alpha, Beta, All), with the first A active.
local initial_footer = footer_text()
assert(initial_footer:find("•", 1, true), "Footer should be bullet separated")
assert(initial_footer:find("Sources:", 1, true), "Footer should be labelled")
assert(initial_footer:find("A", 1, true) and initial_footer:find("B", 1, true), "Footer should show source initials")
local first_a = initial_footer:find("A", 1, true) - 1
local cols = active_cols()
assert(#cols == 1 and cols[1] == first_a, "First source token should be active, got: " .. vim.inspect(cols))
print("PASS: footer shows labelled initials with active source highlighted")

send("<C-s>")
vim.defer_fn(function()
  assert(title():find("%[Beta%]"), "After <C-s> source should be Beta, got: " .. title())

  local text = footer_text()
  local beta_col = text:find("B", 1, true) - 1
  local bcols = active_cols()
  assert(#bcols == 1 and bcols[1] == beta_col, "Active token should follow to Beta")
  print("PASS: <C-s> switched to Beta and moved the highlight")

  send("<C-s>")
  vim.defer_fn(function()
    assert(title():find("%[All%]"), "After second <C-s> source should be All, got: " .. title())

    -- Search across all sources and confirm the source label is shown.
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { "two" })
    vim.defer_fn(function()
      local lines = vim.api.nvim_buf_get_lines(results_buf, 0, -1, false)
      local found = false
      for _, l in ipairs(lines) do
        if l:find("Beta • CatB", 1, true) and l:find("Beta Two", 1, true) then
          found = true
        end
      end
      assert(found, "Search results should be labelled with the source: " .. table.concat(lines, " | "))
      print("PASS: search results show source label")

      config.reset()
      vim.fn.delete(alpha.path, "rf")
      vim.fn.delete(beta.path, "rf")
      print("ALL SOURCE TESTS PASSED!")
      vim.cmd("qall!")
    end, 50)
  end, 50)
end, 50)
