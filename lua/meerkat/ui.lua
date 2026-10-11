local search = require("meerkat.search")

local M = {}

--- Setup custom highlight groups with safe defaults
function M.setup_highlights()
  vim.api.nvim_set_hl(0, "MeerkatCategory", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "MeerkatFolder", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "MeerkatMatch", { default = true, link = "Special" })
  vim.api.nvim_set_hl(0, "MeerkatDescription", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "MeerkatPromptPrefix", { default = true, link = "Identifier" })
  vim.api.nvim_set_hl(0, "MeerkatSource", { default = true, link = "Type" })
  vim.api.nvim_set_hl(0, "MeerkatSourceIndicator", { default = true, fg = "#8a9bb5" })
  vim.api.nvim_set_hl(0, "MeerkatSourceActive", { default = true, fg = "#ff9e64", bold = true })
end

--- Simple fallback picker using vim.ui.select
function M.select(commands, on_select)
  vim.ui.select(commands, {
    prompt = "Meerkat command:",
    format_item = function(item)
      return item.name .. " — " .. (item.description or "")
    end,
  }, function(workflow)
    if workflow and on_select then
      on_select(workflow)
    end
  end)
end

--- Opens the interactive tabbed picker with live fuzzy search.
---
--- `opts.sources` is an ordered list of `{ name = string, path = string }`
--- entries. `opts.default_source` selects the initial source (a source name or
--- "All"). When more than one source is available the results window title
--- shows the active source and `<C-s>` / `<M-s>` cycles through them.
function M.open(commands, on_select, on_dry_run, opts)
  opts = opts or {}
  M.setup_highlights()

  -- Source handling --------------------------------------------------------
  local sources = opts.sources or {}
  local source_names = {}

  for _, source in ipairs(sources) do
    table.insert(source_names, source.name)
  end

  local has_multiple_sources = #source_names > 1

  -- Cycle order: every source, then "All" when it makes sense.
  local source_cycle = {}

  for _, name in ipairs(source_names) do
    table.insert(source_cycle, name)
  end

  if #source_names ~= 1 then
    table.insert(source_cycle, "All")
  end

  local function is_valid_source(name)
    if name == "All" then
      return true
    end

    for _, candidate in ipairs(source_names) do
      if candidate == name then
        return true
      end
    end

    return false
  end

  local current_source = opts.default_source

  if not current_source or not is_valid_source(current_source) then
    current_source = source_cycle[1] or "All"
  end

  local function commands_for_source(name)
    if name == "All" then
      return commands
    end

    local filtered = {}

    for _, workflow in ipairs(commands) do
      if workflow.source == name then
        table.insert(filtered, workflow)
      end
    end

    return filtered
  end

  -- Index (rebuilt whenever the active source changes) ---------------------
  local categories = {}
  local trees = {}
  local all_workflows = {}

  local function build_index(filtered)
    categories = {}
    trees = {}
    all_workflows = {}

    local category_seen = {}

    for _, workflow in ipairs(filtered) do
      local category = workflow.category or "General"

      if not category_seen[category] then
        category_seen[category] = true
        table.insert(categories, category)
        trees[category] = {
          folders = {},
          workflows = {},
          dir = nil, -- absolute dir of the category (set on first workflow)
        }
      end

      local node = trees[category]

      local parts = {}
      local subcategory = workflow.subcategory

      if subcategory and subcategory ~= "" then
        for part in subcategory:gmatch("[^/\\]+") do
          table.insert(parts, part)
        end
      end

      -- Absolute directory containing this workflow's JSON file.
      local file_dir = workflow.file_dir

      -- Category directory = file_dir with the subcategory parts removed.
      local cat_dir = file_dir
      for _ = 1, #parts do
        cat_dir = vim.fn.fnamemodify(cat_dir, ":h")
      end

      if not node.dir and cat_dir ~= nil and cat_dir ~= "" then
        node.dir = cat_dir
      end

      -- Walk/create subfolders, tracking each folder's absolute dir.
      local cur_dir = cat_dir

      for _, part in ipairs(parts) do
        if cur_dir then
          cur_dir = cur_dir .. "/" .. part
        end

        local child = node.folders[part]

        if not child then
          child = {
            folders = {},
            workflows = {},
            dir = cur_dir,
          }
          node.folders[part] = child
        end

        node = child
      end

      table.insert(node.workflows, workflow)
      table.insert(all_workflows, search.index_workflow(workflow))
    end

    table.sort(categories)

    -- Sort entries consistently within folders
    local function sort_tree(node)
      table.sort(node.workflows, function(a, b)
        return a.name:lower() < b.name:lower()
      end)

      for _, folder in pairs(node.folders) do
        sort_tree(folder)
      end
    end

    for _, tree in pairs(trees) do
      sort_tree(tree)
    end
  end

  local current_category = 1
  local current_path = {}
  local current_query = ""
  local line_entries = {}

  -- Source indicator footer is only useful with something to switch between.
  -- Reserve 2 lines when visible: 1 gap + the indicator line itself.
  local show_footer = #source_cycle > 1
  local footer_height = show_footer and 2 or 0

  -- Calculate geometry
  local width = math.max(40, math.min(85, vim.o.columns - 4))
  local prompt_height = 1
  local results_height = math.max(6, math.min(16, vim.o.lines - 8))
  local total_height = prompt_height + 2 + results_height + 2 + footer_height
  local start_row = math.max(1, math.floor((vim.o.lines - total_height) / 2))
  local start_col = math.floor((vim.o.columns - width) / 2)

  -- Create Prompt Window
  local prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].buftype = "nofile"
  vim.bo[prompt_buf].bufhidden = "wipe"
  vim.bo[prompt_buf].swapfile = false

  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    width = width,
    height = prompt_height,
    col = start_col,
    row = start_row,
    style = "minimal",
    border = "rounded",
    title = " Search Workflows ",
    title_pos = "center",
  })

  -- Create Results Window
  local results_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[results_buf].buftype = "nofile"
  vim.bo[results_buf].bufhidden = "wipe"
  vim.bo[results_buf].swapfile = false
  vim.bo[results_buf].modifiable = false

  local results_title = " Meerkat [" .. current_source .. "] "

  local results_win = vim.api.nvim_open_win(results_buf, false, {
    relative = "editor",
    width = width,
    height = results_height,
    col = start_col,
    row = start_row + 3,
    style = "minimal",
    border = "rounded",
    title = results_title,
    title_pos = "center",
  })

  vim.wo[prompt_win].cursorline = false
  vim.wo[results_win].cursorline = true

  local ns_id = vim.api.nvim_create_namespace("meerkat_picker")

  -- Optional source indicator footer (fixed, never scrolls).
  local footer_buf, footer_win

  if show_footer then
    footer_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[footer_buf].buftype = "nofile"
    vim.bo[footer_buf].bufhidden = "wipe"
    vim.bo[footer_buf].swapfile = false
    vim.bo[footer_buf].modifiable = false

    -- Leave one blank row below the results border so the line never touches it.
    local footer_row = math.min(start_row + 5 + results_height, vim.o.lines - 2)

    footer_win = vim.api.nvim_open_win(footer_buf, false, {
      relative = "editor",
      width = width,
      height = 1,
      col = start_col,
      row = footer_row,
      style = "minimal",
      focusable = true,
      zindex = 60,
    })
  end

  --- Draws the first letter of every source, with the active one highlighted.
  local function render_footer()
    if not footer_win or not vim.api.nvim_buf_is_valid(footer_buf) then
      return
    end

    local text = "  Sources:  "
    local spans = {}

    for i, name in ipairs(source_cycle) do
      local letter = name:sub(1, 1):upper()
      local start_col = #text
      text = text .. letter
      spans[i] = { start_col, #text }

      if i < #source_cycle then
        text = text .. "  •  "
      end
    end

    vim.bo[footer_buf].modifiable = true
    vim.api.nvim_buf_set_lines(footer_buf, 0, -1, false, { text })
    vim.bo[footer_buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(footer_buf, ns_id, 0, -1)
    vim.api.nvim_buf_add_highlight(footer_buf, ns_id, "MeerkatSourceIndicator", 0, 0, #text)

    for i, name in ipairs(source_cycle) do
      if name == current_source and spans[i] then
        vim.api.nvim_buf_add_highlight(
          footer_buf,
          ns_id,
          "MeerkatSourceActive",
          0,
          spans[i][1],
          spans[i][2]
        )
      end
    end
  end

  local function update_title()
    results_title = " Meerkat [" .. current_source .. "] "

    if vim.api.nvim_win_is_valid(results_win) then
      pcall(vim.api.nvim_win_set_config, results_win, {
        title = results_title,
        title_pos = "center",
      })
    end
  end

  local function get_current_node()
    local node = trees[categories[current_category]]
    if not node then
      return nil
    end

    for _, part in ipairs(current_path) do
      node = node.folders[part]
      if not node then
        return nil
      end
    end

    return node
  end

  local is_closed = false
  local function close()
    if is_closed then
      return
    end
    is_closed = true

    if vim.api.nvim_win_is_valid(prompt_win) then
      vim.api.nvim_win_close(prompt_win, true)
    end
    if vim.api.nvim_win_is_valid(results_win) then
      vim.api.nvim_win_close(results_win, true)
    end
    if footer_win and vim.api.nvim_win_is_valid(footer_win) then
      vim.api.nvim_win_close(footer_win, true)
    end
  end

  local function render()
    if not vim.api.nvim_buf_is_valid(results_buf) then
      return
    end

    local lines = {}
    line_entries = {}
    local highlights = {}
    local desc_sep = "  —  "

    if current_query ~= "" then
      -- Search / Filter View
      local matches = search.filter(all_workflows, current_query)

      if #matches == 0 then
        table.insert(lines, "  No workflows matching \"" .. current_query .. "\"")
        table.insert(lines, "  (Press <BS> to clear query)")
      else
        table.insert(lines, "  Matches (" .. #matches .. "):")
        table.insert(lines, "")

        for _, match_info in ipairs(matches) do
          local item = match_info.item
          local wf = item.workflow

          local label = item.cat_path
          if has_multiple_sources and item.source ~= "" then
            label = item.source .. " • " .. item.cat_path
          end

          local prefix = "  [" .. label .. "] "
          local name_start = #prefix
          local line = prefix .. wf.name

          local cat_start = 2
          local cat_end = 2 + #label + 2

          table.insert(highlights, {
            hl = "MeerkatCategory",
            line = #lines,
            col_start = cat_start,
            col_end = cat_end,
          })

          if has_multiple_sources and item.source ~= "" then
            table.insert(highlights, {
              hl = "MeerkatSource",
              line = #lines,
              col_start = 3,
              col_end = 3 + #item.source,
            })
          end

          if wf.description and wf.description ~= "" then
            local desc_start = #line + #desc_sep
            line = line .. desc_sep .. wf.description
            table.insert(highlights, {
              hl = "MeerkatDescription",
              line = #lines,
              col_start = desc_start,
              col_end = #line,
            })
          end

          for _, pos in ipairs(match_info.positions) do
            local h_col = name_start + pos
            if h_col < #line then
              table.insert(highlights, {
                hl = "MeerkatMatch",
                line = #lines,
                col_start = h_col,
                col_end = h_col + 1,
              })
            end
          end

          table.insert(lines, line)
          line_entries[#lines] = {
            type = "workflow",
            workflow = wf,
          }
        end
      end
    else
      -- Category Browse View
      local tabs = {}
      local tab_positions = {}
      local current_col = 0

      for i, category in ipairs(categories) do
        local tab_str
        if i == current_category then
          tab_str = "[" .. category .. "]"
        else
          tab_str = " " .. category .. " "
        end

        table.insert(tab_positions, {
          is_active = (i == current_category),
          col_start = current_col,
          col_end = current_col + #tab_str,
        })
        current_col = current_col + #tab_str + 3
        table.insert(tabs, tab_str)
      end

      table.insert(lines, table.concat(tabs, "   "))

      for _, tp in ipairs(tab_positions) do
        if tp.is_active then
          table.insert(highlights, {
            hl = "MeerkatCategory",
            line = 0,
            col_start = tp.col_start,
            col_end = tp.col_end,
          })
        end
      end

      if #current_path > 0 then
        local breadcrumb = table.concat(current_path, " / ") .. " /"
        table.insert(lines, breadcrumb)
        table.insert(highlights, {
          hl = "MeerkatFolder",
          line = #lines - 1,
          col_start = 0,
          col_end = #breadcrumb,
        })
      end

      table.insert(lines, "")

      local node = get_current_node()
      if node then
        local folder_names = {}
        for name in pairs(node.folders) do
          table.insert(folder_names, name)
        end
        table.sort(folder_names, function(a, b)
          return a:lower() < b:lower()
        end)

        for _, name in ipairs(folder_names) do
          local line = "  > " .. name .. "/"
          table.insert(lines, line)
          table.insert(highlights, {
            hl = "MeerkatFolder",
            line = #lines - 1,
            col_start = 2,
            col_end = #line,
          })
          local folder_node = node.folders[name]
          line_entries[#lines] = {
            type = "folder",
            name = name,
            dir = folder_node and folder_node.dir,
          }
        end

        for _, workflow in ipairs(node.workflows) do
          local line = "  " .. workflow.name
          if workflow.description and workflow.description ~= "" then
            local desc_start = #line + #desc_sep
            line = line .. desc_sep .. workflow.description
            table.insert(highlights, {
              hl = "MeerkatDescription",
              line = #lines,
              col_start = desc_start,
              col_end = #line,
            })
          end

          table.insert(lines, line)
          line_entries[#lines] = {
            type = "workflow",
            workflow = workflow,
          }
        end

        if #folder_names == 0 and #node.workflows == 0 then
          table.insert(lines, "  (Empty folder)")
        end
      end
    end

    vim.bo[results_buf].modifiable = true
    vim.api.nvim_buf_set_lines(results_buf, 0, -1, false, lines)
    vim.bo[results_buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(results_buf, ns_id, 0, -1)
    for _, h in ipairs(highlights) do
      pcall(
        vim.api.nvim_buf_add_highlight,
        results_buf,
        ns_id,
        h.hl,
        h.line,
        h.col_start,
        h.col_end
      )
    end

    local first_entry = nil
    for line_nr = 1, #lines do
      if line_entries[line_nr] then
        first_entry = line_nr
        break
      end
    end

    if vim.api.nvim_win_is_valid(results_win) then
      local cur_line = vim.api.nvim_win_get_cursor(results_win)[1]
      if not line_entries[cur_line] and first_entry then
        vim.api.nvim_win_set_cursor(results_win, { first_entry, 0 })
      elseif cur_line > #lines and first_entry then
        vim.api.nvim_win_set_cursor(results_win, { first_entry, 0 })
      end
    end

    render_footer()
  end

  local function move_selection(delta)
    if not vim.api.nvim_win_is_valid(results_win) then
      return
    end

    local line_count = vim.api.nvim_buf_line_count(results_buf)
    local cur_line = vim.api.nvim_win_get_cursor(results_win)[1]

    local selectable = {}
    for l = 1, line_count do
      if line_entries[l] then
        table.insert(selectable, l)
      end
    end

    if #selectable == 0 then
      return
    end

    local cur_idx = 1
    for i, l in ipairs(selectable) do
      if l == cur_line then
        cur_idx = i
        break
      elseif l > cur_line and cur_idx == 1 then
        cur_idx = i
      end
    end

    local next_idx = cur_idx + delta
    if next_idx < 1 then
      next_idx = 1
    elseif next_idx > #selectable then
      next_idx = #selectable
    end

    vim.api.nvim_win_set_cursor(results_win, { selectable[next_idx], 0 })
  end

  local function reset_query()
    if vim.api.nvim_buf_is_valid(prompt_buf) then
      vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { "" })
    end
    current_query = ""
  end

  local function switch_category(direction)
    if #categories == 0 then
      return
    end

    current_category = ((current_category - 1 + direction) % #categories) + 1
    current_path = {}
    render()
  end

  local function switch_source()
    if #source_cycle <= 1 then
      return
    end

    local idx = 1
    for i, name in ipairs(source_cycle) do
      if name == current_source then
        idx = i
        break
      end
    end

    idx = (idx % #source_cycle) + 1
    current_source = source_cycle[idx]
    current_category = 1
    current_path = {}

    build_index(commands_for_source(current_source))
    reset_query()
    update_title()
    render()
  end

  local function go_back()
    if #current_path > 0 then
      table.remove(current_path)
      render()
    end
  end

  local function select_current()
    if not vim.api.nvim_win_is_valid(results_win) then
      return
    end

    local line = vim.api.nvim_win_get_cursor(results_win)[1]
    local entry = line_entries[line]

    if not entry then
      return
    end

    if entry.type == "folder" then
      table.insert(current_path, entry.name)
      reset_query()
      render()
    elseif entry.type == "workflow" then
      local workflow = entry.workflow
      close()
      if on_select then
        on_select(workflow)
      end
    end
  end

  local function dry_run_current()
    if not vim.api.nvim_win_is_valid(results_win) then
      return
    end

    local line = vim.api.nvim_win_get_cursor(results_win)[1]
    local entry = line_entries[line]

    if not entry or entry.type ~= "workflow" then
      return
    end

    local workflow = entry.workflow
    close()
    if on_dry_run then
      on_dry_run(workflow)
    end
  end

  --- Opens the highlighted folder / workflow's directory in the OS file manager.
  local function open_current_dir()
    if not vim.api.nvim_win_is_valid(results_win) then
      return
    end

    local line = vim.api.nvim_win_get_cursor(results_win)[1]
    local entry = line_entries[line]

    if not entry then
      return
    end

    local dir

    if entry.type == "workflow" then
      local wf = entry.workflow

      if wf.file_dir and wf.file_dir ~= "" then
        dir = wf.file_dir
      elseif wf.source_path and wf.source_path ~= "" then
        dir = vim.fn.fnamemodify(wf.source_path, ":h")
      end
    elseif entry.type == "folder" then
      dir = entry.dir
    end

    if not dir or dir == "" then
      vim.notify("No folder available for this entry", vim.log.levels.WARN)
      return
    end

    local ok, err = pcall(vim.ui.open, dir)
    if not ok then
      vim.notify("Could not open folder: " .. tostring(err), vim.log.levels.ERROR)
    end
  end

  local function focus_prompt()
    if vim.api.nvim_win_is_valid(prompt_win) then
      vim.api.nvim_set_current_win(prompt_win)
      vim.cmd("startinsert!")
    end
  end

  -- Prompt buffer mappings (Insert + Normal mode)
  vim.keymap.set({ "i", "n" }, "<CR>", select_current, { buffer = prompt_buf, silent = true, nowait = true })
  vim.keymap.set({ "i", "n" }, "<C-d>", dry_run_current, { buffer = prompt_buf, silent = true, nowait = true })
  vim.keymap.set({ "i", "n" }, "<Down>", function() move_selection(1) end, { buffer = prompt_buf, silent = true })
  vim.keymap.set({ "i", "n" }, "<C-n>", function() move_selection(1) end, { buffer = prompt_buf, silent = true })
  vim.keymap.set({ "i", "n" }, "<C-j>", function() move_selection(1) end, { buffer = prompt_buf, silent = true })
  vim.keymap.set({ "i", "n" }, "<Up>", function() move_selection(-1) end, { buffer = prompt_buf, silent = true })
  vim.keymap.set({ "i", "n" }, "<C-p>", function() move_selection(-1) end, { buffer = prompt_buf, silent = true })
  vim.keymap.set({ "i", "n" }, "<C-k>", function() move_selection(-1) end, { buffer = prompt_buf, silent = true })

  vim.keymap.set({ "i", "n" }, "<Tab>", function()
    if current_query == "" then
      switch_category(1)
    else
      move_selection(1)
    end
  end, { buffer = prompt_buf, silent = true })

  vim.keymap.set({ "i", "n" }, "<S-Tab>", function()
    if current_query == "" then
      switch_category(-1)
    else
      move_selection(-1)
    end
  end, { buffer = prompt_buf, silent = true })

  vim.keymap.set({ "i", "n" }, "<C-s>", switch_source, { buffer = prompt_buf, silent = true, nowait = true })
  vim.keymap.set({ "i", "n" }, "<M-s>", switch_source, { buffer = prompt_buf, silent = true, nowait = true })
  vim.keymap.set({ "i", "n" }, "<C-o>", open_current_dir, { buffer = prompt_buf, silent = true, nowait = true })

  vim.keymap.set("i", "<BS>", function()
    local text = vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or ""
    if text == "" and #current_path > 0 then
      go_back()
      return ""
    end
    return "<BS>"
  end, { buffer = prompt_buf, expr = true, silent = true })

  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    if vim.api.nvim_win_is_valid(results_win) then
      vim.api.nvim_set_current_win(results_win)
      vim.cmd("stopinsert")
    else
      close()
    end
  end, { buffer = prompt_buf, silent = true, nowait = true })

  vim.keymap.set({ "i", "n" }, "<C-c>", close, { buffer = prompt_buf, silent = true, nowait = true })

  -- Results buffer mappings (Normal mode)
  local function map_results(key, fn)
    vim.keymap.set("n", key, fn, { buffer = results_buf, silent = true, nowait = true })
  end

  map_results("j", function() move_selection(1) end)
  map_results("<Down>", function() move_selection(1) end)
  map_results("<C-n>", function() move_selection(1) end)
  map_results("k", function() move_selection(-1) end)
  map_results("<Up>", function() move_selection(-1) end)
  map_results("<C-p>", function() move_selection(-1) end)

  map_results("<Tab>", function()
    if current_query == "" then switch_category(1) else move_selection(1) end
  end)
  map_results("<S-Tab>", function()
    if current_query == "" then switch_category(-1) else move_selection(-1) end
  end)
  map_results("l", function()
    if current_query == "" then switch_category(1) end
  end)
  map_results("h", function()
    if current_query == "" then switch_category(-1) end
  end)

  map_results("<C-s>", switch_source)
  map_results("<M-s>", switch_source)
  map_results("<C-o>", open_current_dir)

  map_results("<CR>", select_current)
  map_results("<C-d>", dry_run_current)
  map_results("<BS>", go_back)
  map_results("<S-BS>", go_back)
  map_results("u", go_back)

  map_results("i", focus_prompt)
  map_results("a", focus_prompt)
  map_results("/", focus_prompt)

  map_results("q", close)
  map_results("<Esc>", close)
  map_results("<C-c>", close)

  -- The results list is display-only: never allow insert mode in it.
  vim.api.nvim_create_autocmd("InsertEnter", {
    buffer = results_buf,
    callback = function()
      vim.cmd("stopinsert")
    end,
  })

  -- Watch prompt buffer for live query changes
  vim.api.nvim_buf_attach(prompt_buf, false, {
    on_lines = function()
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(prompt_buf) then
          return
        end
        local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
        local q = vim.trim(lines[1] or "")
        if q ~= current_query then
          current_query = q
          render()
        end
      end)
    end,
  })

  -- Window cleanup on close
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(prompt_win),
    once = true,
    callback = close,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(results_win),
    once = true,
    callback = close,
  })

  -- The footer is decorative: if it ever gains focus, bounce back to the prompt.
  if footer_win then
    vim.api.nvim_create_autocmd("WinEnter", {
      pattern = tostring(footer_win),
      callback = function()
        if not is_closed and vim.api.nvim_win_is_valid(prompt_win) then
          vim.api.nvim_set_current_win(prompt_win)
          vim.cmd("startinsert!")
        end
      end,
    })
  end

  build_index(commands_for_source(current_source))
  update_title()
  render()
  vim.api.nvim_set_current_win(prompt_win)
  vim.cmd("startinsert!")
end

return M
