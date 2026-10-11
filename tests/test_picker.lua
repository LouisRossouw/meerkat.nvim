local meerkat = require("meerkat")
meerkat.open()

local wins = vim.api.nvim_tabpage_list_wins(0)
local prompt_win, results_win, prompt_buf, results_buf

for _, w in ipairs(wins) do
  local cfg = vim.api.nvim_win_get_config(w)
  if cfg.title and cfg.title[1] and cfg.title[1][1] then
    local t = cfg.title[1][1]
    if t:find("Search") then
      prompt_win = w
      prompt_buf = vim.api.nvim_win_get_buf(w)
    elseif t:find("Meerkat") then
      results_win = w
      results_buf = vim.api.nvim_win_get_buf(w)
    end
  end
end

assert(prompt_win and results_win, "Both windows should exist")
print("PASS: Windows created successfully")

local init_lines = vim.api.nvim_buf_get_lines(results_buf, 0, -1, false)
print("Initial lines in results buffer:")
for i, l in ipairs(init_lines) do
  print(string.format("  [%d] %s", i, l))
end

-- Test typing 'maya' into prompt buffer
vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { "maya" })

vim.defer_fn(function()
  local search_lines = vim.api.nvim_buf_get_lines(results_buf, 0, -1, false)
  print("Search lines for 'maya':")
  for i, l in ipairs(search_lines) do
    print(string.format("  [%d] %s", i, l))
  end

  local found_maya = false
  for _, l in ipairs(search_lines) do
    if l:find("reset%-user%-maya%-adsk") or l:find("maya") then
      found_maya = true
      break
    end
  end
  assert(found_maya, "Should find Maya workflow")
  print("PASS: Live search matched Maya workflow")

  -- Test typing 'connect'
  vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { "connect" })
  vim.defer_fn(function()
    local conn_lines = vim.api.nvim_buf_get_lines(results_buf, 0, -1, false)
    print("Search lines for 'connect':")
    for i, l in ipairs(conn_lines) do
      print(string.format("  [%d] %s", i, l))
    end
    local found_conn = false
    for _, l in ipairs(conn_lines) do
      if l:find("Connect Host") then
        found_conn = true
        break
      end
    end
    assert(found_conn, "Should find Connect Host")
    print("PASS: Live search matched 'Connect Host'")

    -- Test clearing search
    vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { "" })
    vim.defer_fn(function()
      local restored = vim.api.nvim_buf_get_lines(results_buf, 0, -1, false)
      print("Restored category browse view line 1: " .. (restored[1] or ""))
      assert(restored[1]:find("%["), "Should restore category tabs")
      print("PASS: Restoring browse view upon clearing search query")

      -- Test category switching via <Tab>
      -- Switch to next category using remapped key
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "m", false)
      vim.defer_fn(function()
        local cat2_lines = vim.api.nvim_buf_get_lines(results_buf, 0, -1, false)
        print("After <Tab> switch, line 1: " .. (cat2_lines[1] or ""))
        assert(cat2_lines[1]:find("%["), "An active (bracketed) category should be shown")
        assert(
          cat2_lines[1] ~= restored[1],
          "The active category should change after <Tab>"
        )
        print("PASS: <Tab> switched the active category")
        print("ALL TESTS PASSED!")
        vim.cmd("qall!")
      end, 50)
    end, 50)
  end, 50)
end, 50)
