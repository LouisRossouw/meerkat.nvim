local input = require("meerkat.input")
local runner = require("meerkat.runner")
local meerkat = require("meerkat")

print("=== Starting Feature Tests ===")

-- 1. Test Input defaults with environment variables
vim.env.DOOHI_TEST_HOST = "my-env-host.net"
local env_wf = {
  inputs = {
    { name = "host", default = "$DOOHI_TEST_HOST" },
  },
}

-- Mock vim.ui.input to simulate pressing Enter with default value
local orig_input = vim.ui.input
vim.ui.input = function(opts, on_confirm)
  -- User pressed enter without typing anything, accepting default
  on_confirm(opts.default)
end

input.collect(env_wf, function(res)
  assert(res.host == "my-env-host.net", "Env variable default should resolve to 'my-env-host.net'")
  print("PASS: Environment variable default resolution")
end)

-- 2. Test Input select choices
local select_wf = {
  inputs = {
    {
      name = "env",
      type = "select",
      choices = { "staging", "production" },
    },
  },
}

local orig_select = vim.ui.select
vim.ui.select = function(items, opts, on_choice)
  -- Select second option
  on_choice(items[2])
end

input.collect(select_wf, function(res)
  assert(res.env == "production", "Select choice should return 'production'")
  print("PASS: Select choices input handling")
end)

vim.ui.input = orig_input
vim.ui.select = orig_select

-- 3. Test New Steps: vim_command, lua_command, clipboard
vim.g.meerkat_vim_ran = false
_G.meerkat_lua_ran = false

local test_steps_wf = {
  name = "Steps Test",
  steps = {
    {
      type = "vim_command",
      command = "let g:meerkat_vim_ran = 1",
    },
    {
      type = "lua_command",
      code = "_G.meerkat_lua_ran = true",
    },
    {
      type = "clipboard",
      text = "copied-ssh-key-42",
    },
  },
}

runner.run_workflow(test_steps_wf, {})

vim.defer_fn(function()
  assert(vim.g.meerkat_vim_ran == 1, "vim_command should set g:meerkat_vim_ran")
  assert(_G.meerkat_lua_ran == true, "lua_command should set _G.meerkat_lua_ran")
  assert(vim.fn.getreg("+") == "copied-ssh-key-42", "clipboard step should copy text to register +")
  print("PASS: New steps execution (vim_command, lua_command, clipboard)")

  -- 4. Test Dry Run Window
  local dry_run_wf = {
    name = "Deploy API",
    description = "Deploys api to host",
    steps = {
      {
        type = "ssh_command",
        host = "{target_host}",
        command = "systemctl restart api",
      },
      {
        type = "notify",
        message = "Deployed to {target_host}",
      },
    },
  }

  runner.dry_run(dry_run_wf, { target_host = "api-prod-01" })

  local wins = vim.api.nvim_tabpage_list_wins(0)
  local dry_win, dry_buf

  for _, w in ipairs(wins) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.title and cfg.title[1] and cfg.title[1][1] and cfg.title[1][1]:find("Dry Run") then
      dry_win = w
      dry_buf = vim.api.nvim_win_get_buf(w)
      break
    end
  end

  assert(dry_win and dry_buf, "Dry Run floating window should be open")
  local dry_lines = vim.api.nvim_buf_get_lines(dry_buf, 0, -1, false)

  local found_host = false
  local found_cmd = false
  for _, l in ipairs(dry_lines) do
    if l:find("api%-prod%-01") then found_host = true end
    if l:find("systemctl restart api") then found_cmd = true end
  end

  assert(found_host, "Dry Run lines should show expanded target_host 'api-prod-01'")
  assert(found_cmd, "Dry Run lines should show expanded command 'systemctl restart api'")
  print("PASS: Dry Run buffer expansion and rendering")

  -- Close dry run window with 'q'
  vim.api.nvim_set_current_win(dry_win)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("q", true, false, true), "x", false)

  assert(not vim.api.nvim_win_is_valid(dry_win), "Dry run window should close after pressing 'q'")
  print("PASS: Dry Run window close on 'q'")

  print("=== ALL FEATURE TESTS PASSED ===")
  vim.cmd("qall!")
end, 100)
