local M = {}

local function expand(value, inputs)
  if type(value) == "string" then
    return (value:gsub("{([%w_%.]+)}", function(key)
      local current = inputs
      for part in key:gmatch("[^%.]+") do
        if type(current) == "table" then
          current = current[part]
        else
          current = nil
          break
        end
      end
      if current ~= nil then
        return tostring(current)
      end
      return tostring(inputs[key] or "")
    end))
  elseif type(value) == "table" then
    local result = {}
    for key, item in pairs(value) do
      result[key] = expand(item, inputs)
    end
    return result
  end

  return value
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

local function confirm(step, next_step)
  vim.ui.select({ "Yes", "No" }, {
    prompt = step.message or "Are you sure?",
  }, function(choice)
    if choice == "Yes" then
      next_step()
    else
      notify("Workflow cancelled", vim.log.levels.WARN)
    end
  end)
end

local function run_local(step, next_step)
  local command = step.command

  if type(command) ~= "table" or #command == 0 then
    notify("local_command requires a command array", vim.log.levels.ERROR)
    return
  end

  local ok, err = pcall(vim.fn.jobstart, command, {
    detach = true,
  })

  if not ok or (type(err) == "number" and err <= 0) then
    notify("Could not launch local command", vim.log.levels.ERROR)
    return
  end

  next_step()
end

local function run_steps(workflow, inputs)
  local index = 1
  local terminal_count = 0
  local steps = workflow.steps or {}

  local run_next

  local function next_step()
    index = index + 1
    vim.schedule(run_next)
  end

  local function open_terminal(command, wait_for_exit)
    if terminal_count > 0 then
      vim.cmd("vsplit")
    end

    terminal_count = terminal_count + 1

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)

    local job = vim.fn.termopen(command, {
      on_exit = function(_, exit_code)
        if wait_for_exit then
          vim.schedule(function()
            if exit_code == 0 then
              next_step()
            else
              notify(
                "Command failed with exit code " .. exit_code,
                vim.log.levels.ERROR
              )
            end
          end)
        end
      end,
    })

    if job <= 0 then
      notify("Failed to start terminal command", vim.log.levels.ERROR)
      return false
    end

    vim.cmd("startinsert")
    return true
  end

  local last_step = nil

  run_next = function()
    local original = steps[index]

    if not original then
      -- If the last step was already a user-facing notification (notify, clipboard),
      -- do not overwrite it with a generic completion message.
      if not last_step or (last_step.type ~= "notify" and last_step.type ~= "clipboard") then
        notify("Workflow steps completed")
      end
      return
    end

    local step = expand(original, inputs)
    last_step = step

    if step.type == "confirm" then
      confirm(step, next_step)

    elseif step.type == "notify" then
      notify(step.message or "Workflow update")
      next_step()

    elseif step.type == "sleep" then
      local seconds = tonumber(step.seconds)

      if not seconds or seconds < 0 or seconds > 3600 then
        notify("Invalid sleep duration", vim.log.levels.ERROR)
        return
      end

      vim.defer_fn(next_step, math.floor(seconds * 1000))

    elseif step.type == "local_command" then
      run_local(step, next_step)

    elseif step.type == "ssh_terminal" then
      if not step.host or step.host == "" then
        notify("ssh_terminal requires a host", vim.log.levels.ERROR)
        return
      end

      open_terminal({ "ssh", step.host }, false)
      next_step()

    elseif step.type == "ssh_command" then
      if not step.host or step.host == "" or not step.command then
        notify("ssh_command requires host and command", vim.log.levels.ERROR)
        return
      end

      open_terminal({
        "ssh",
        "-t",
        step.host,
        step.command,
      }, true)

    elseif step.type == "vim_command" then
      if not step.command or step.command == "" then
        notify("vim_command requires a command string", vim.log.levels.ERROR)
        return
      end

      local ok, err = pcall(vim.cmd, step.command)
      if not ok then
        notify("vim_command error: " .. tostring(err), vim.log.levels.ERROR)
        return
      end
      next_step()

    elseif step.type == "lua_command" then
      if not step.code or step.code == "" then
        notify("lua_command requires a code string", vim.log.levels.ERROR)
        return
      end

      local fn, compile_err = (loadstring or load)(step.code)
      if not fn then
        notify("lua_command compile error: " .. tostring(compile_err), vim.log.levels.ERROR)
        return
      end

      local ok, run_err = pcall(fn)
      if not ok then
        notify("lua_command runtime error: " .. tostring(run_err), vim.log.levels.ERROR)
        return
      end
      next_step()

    elseif step.type == "clipboard" then
      local text = step.text or ""
      vim.fn.setreg("+", text)
      local preview = text:len() > 30 and (text:sub(1, 27) .. "...") or text
      notify("Copied to clipboard: " .. preview)
      next_step()

    elseif step.type == "open_url" then
      if not step.url or step.url == "" then
        notify("open_url requires a url", vim.log.levels.ERROR)
        return
      end

      if vim.ui and vim.ui.open then
        vim.ui.open(step.url)
      elseif vim.fn.has("win32") == 1 then
        vim.fn.jobstart({ "cmd.exe", "/c", "start", "", step.url }, { detach = true })
      elseif vim.fn.has("mac") == 1 then
        vim.fn.jobstart({ "open", step.url }, { detach = true })
      else
        vim.fn.jobstart({ "xdg-open", step.url }, { detach = true })
      end
      next_step()

    elseif step.type == "http_request" then
      if not step.url or step.url == "" then
        notify("http_request requires a url", vim.log.levels.ERROR)
        return
      end

      local method = (step.method or "GET"):upper()
      local cmd = { "curl", "-s", "-X", method, step.url }

      if step.body and step.body ~= "" then
        table.insert(cmd, "-d")
        table.insert(cmd, step.body)
      end

      if step.headers and type(step.headers) == "table" then
        for k, v in pairs(step.headers) do
          table.insert(cmd, "-H")
          table.insert(cmd, k .. ": " .. v)
        end
      end

      local stdout_chunks = {}
      local ok = pcall(vim.fn.jobstart, cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if data then
            for _, line in ipairs(data) do
              table.insert(stdout_chunks, line)
            end
          end
        end,
        on_exit = function(_, exit_code)
          if exit_code == 0 then
            local response_text = vim.trim(table.concat(stdout_chunks, "\n"))
            if step.save_to and step.save_to ~= "" then
              local ok_json, parsed = pcall(vim.json.decode, response_text)
              if ok_json and type(parsed) == "table" then
                setmetatable(parsed, {
                  __tostring = function()
                    return response_text
                  end,
                })
                inputs[step.save_to] = parsed
              else
                inputs[step.save_to] = response_text
              end
            end
            notify("HTTP " .. method .. " request succeeded: " .. step.url)
            next_step()
          else
            notify("HTTP request failed with exit code " .. exit_code, vim.log.levels.ERROR)
          end
        end,
      })

      if not ok then
        notify("Could not launch curl command", vim.log.levels.ERROR)
      end

    else
      notify("Unknown step type: " .. tostring(step.type), vim.log.levels.ERROR)
    end
  end

  run_next()
end

--- Runs workflow steps in a new tab
function M.run_workflow(workflow, inputs)
  vim.cmd("tabnew")
  run_steps(workflow, inputs)
end

--- Displays a dry run inspection window showing expanded steps without executing them
function M.dry_run(workflow, inputs)
  inputs = inputs or {}
  local lines = {}

  table.insert(lines, "  Workflow: " .. (workflow.name or "Untitled"))
  if workflow.description and workflow.description ~= "" then
    table.insert(lines, "  Description: " .. workflow.description)
  end
  table.insert(lines, "")

  table.insert(lines, "  ─── Inputs ──────────────────────────────────────────")
  local has_inputs = false
  for k, v in pairs(inputs) do
    has_inputs = true
    table.insert(lines, string.format("    • %-16s = %s", k, tostring(v)))
  end
  if not has_inputs then
    table.insert(lines, "    (No inputs)")
  end
  table.insert(lines, "")

  table.insert(lines, "  ─── Steps Pipeline ──────────────────────────────────")
  local steps = workflow.steps or {}
  for i, raw_step in ipairs(steps) do
    local step = expand(raw_step, inputs)
    table.insert(lines, string.format("  [%d] Type: %s", i, step.type or "unknown"))

    if step.type == "confirm" then
      table.insert(lines, "      prompt: " .. (step.message or "Are you sure?"))
    elseif step.type == "notify" then
      table.insert(lines, "      message: " .. (step.message or ""))
    elseif step.type == "sleep" then
      table.insert(lines, "      duration: " .. tostring(step.seconds) .. "s")
    elseif step.type == "local_command" then
      local cmd_str = type(step.command) == "table" and table.concat(step.command, " ") or tostring(step.command)
      table.insert(lines, "      exec: " .. cmd_str)
    elseif step.type == "ssh_terminal" then
      table.insert(lines, "      ssh terminal: ssh " .. tostring(step.host))
    elseif step.type == "ssh_command" then
      table.insert(lines, "      ssh command: ssh -t " .. tostring(step.host) .. " " .. tostring(step.command))
    elseif step.type == "vim_command" then
      table.insert(lines, "      vim command: " .. tostring(step.command))
    elseif step.type == "lua_command" then
      table.insert(lines, "      lua code: " .. tostring(step.code))
    elseif step.type == "clipboard" then
      table.insert(lines, "      copy text: " .. tostring(step.text))
    elseif step.type == "open_url" then
      table.insert(lines, "      open url: " .. tostring(step.url))
    elseif step.type == "http_request" then
      local save_str = (step.save_to and step.save_to ~= "") and (" -> save to: {" .. step.save_to .. "}") or ""
      table.insert(lines, string.format("      %s %s%s", step.method or "GET", tostring(step.url), save_str))
    else
      for k, v in pairs(step) do
        if k ~= "type" then
          table.insert(lines, string.format("      %s: %s", k, vim.inspect(v)))
        end
      end
    end
    table.insert(lines, "")
  end

  table.insert(lines, "  ─────────────────────────────────────────────────────")
  table.insert(lines, "  [<CR>] Execute this workflow     [q / <Esc>] Close")

  local width = math.max(55, math.min(90, vim.o.columns - 4))
  local height = math.max(8, math.min(#lines + 2, vim.o.lines - 6))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Dry Run: " .. (workflow.name or "") .. " ",
    title_pos = "center",
  })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<CR>", function()
    close()
    M.run_workflow(workflow, inputs)
  end, { buffer = buf, silent = true, nowait = true })
end

return M
