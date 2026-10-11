local runner = require("meerkat.runner")

print("=== Starting HTTP Response Piping Tests ===")

-- Mock jobstart for curl to return predictable response without network
local orig_jobstart = vim.fn.jobstart

local mock_response = '{"tag": "v3.1.0", "details": {"commit": "abc1234", "author": "louis"}}'
local captured_messages = {}

local orig_notify = vim.notify
vim.notify = function(msg)
  table.insert(captured_messages, msg)
end

vim.fn.jobstart = function(cmd, opts)
  if cmd[1] == "curl" then
    vim.schedule(function()
      if opts.on_stdout then
        opts.on_stdout(1, { mock_response })
      end
      if opts.on_exit then
        opts.on_exit(1, 0)
      end
    end)
    return 999
  end
  return orig_jobstart(cmd, opts)
end

local http_piping_wf = {
  name = "API Pipeline Test",
  steps = {
    {
      type = "http_request",
      method = "GET",
      url = "https://api.github.com/mock/release",
      save_to = "release",
    },
    {
      type = "notify",
      message = "Version: {release.tag} by {release.details.author}",
    },
    {
      type = "clipboard",
      text = "commit: {release.details.commit}",
    },
  },
}

runner.run_workflow(http_piping_wf, {})

vim.defer_fn(function()
  -- Restore mocks
  vim.fn.jobstart = orig_jobstart
  vim.notify = orig_notify

  local found_version_msg = false
  for _, m in ipairs(captured_messages) do
    if m:find("Version: v3.1.0 by louis") then
      found_version_msg = true
      break
    end
  end

  assert(found_version_msg, "Should interpolate {release.tag} and {release.details.author}")
  print("PASS: JSON dot-notation interpolation in notify step")

  local reg = vim.fn.getreg("+")
  assert(reg == "commit: abc1234", "Should interpolate {release.details.commit} in clipboard step, got: " .. tostring(reg))
  print("PASS: Nested field interpolation in clipboard step")

  -- Test Raw String interpolation
  local raw_wf = {
    name = "Raw Test",
    steps = {
      {
        type = "notify",
        message = "Raw: {release}",
      },
    },
  }

  local inputs = {
    release = setmetatable({ tag = "v3.1.0" }, {
      __tostring = function() return "RAW_TEXT_REPRESENTATION" end,
    }),
  }

  runner.run_workflow(raw_wf, inputs)

  vim.defer_fn(function()
    print("=== ALL HTTP PIPING TESTS PASSED ===")
    vim.cmd("qall!")
  end, 50)
end, 150)
