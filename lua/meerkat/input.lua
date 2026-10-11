local M = {}

--- Resolves default value, supporting environment variables ($ENV_VAR)
local function resolve_default(default_val)
  if type(default_val) ~= "string" then
    return default_val
  end

  if default_val:sub(1, 1) == "$" then
    local env_var = default_val:sub(2)
    local val = os.getenv(env_var)
    return val or ""
  end

  return default_val
end

--- Prompts the user sequentially for any inputs defined in the workflow
function M.collect(workflow, callback)
  local inputs = {}
  local definitions = workflow.inputs or {}
  local index = 1

  local function next_input()
    local definition = definitions[index]

    if not definition then
      callback(inputs)
      return
    end

    local prompt_str = definition.prompt or definition.name
    local default_val = resolve_default(definition.default)

    if definition.type == "select" or (definition.choices and #definition.choices > 0) then
      local choices = definition.choices or {}

      vim.ui.select(choices, {
        prompt = prompt_str .. ": ",
        format_item = function(item)
          if type(item) == "table" and item.label then
            return item.label
          end
          return tostring(item)
        end,
      }, function(choice)
        if choice == nil then
          if default_val and default_val ~= "" then
            choice = default_val
          else
            vim.notify("Workflow cancelled.", vim.log.levels.WARN)
            return
          end
        end

        local val = choice
        if type(choice) == "table" and choice.value ~= nil then
          val = choice.value
        end

        inputs[definition.name] = tostring(val)
        index = index + 1
        next_input()
      end)
    else
      local default_text = default_val and tostring(default_val) or ""

      vim.ui.input({
        prompt = prompt_str .. ": ",
        default = default_text,
      }, function(value)
        if value == nil then
          vim.notify("Workflow cancelled.", vim.log.levels.WARN)
          return
        end

        if value == "" and default_text ~= "" then
          value = default_text
        end

        if value == "" then
          vim.notify("Workflow cancelled: empty input.", vim.log.levels.WARN)
          return
        end

        inputs[definition.name] = value
        index = index + 1
        next_input()
      end)
    end
  end

  next_input()
end

return M
