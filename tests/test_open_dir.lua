-- Tests for the <C-o> "open folder in file manager" shortcut.
local meerkat = require("meerkat")
local config = require("meerkat.config")

local function write_file(path, contents)
  local file = assert(io.open(path, "w"))
  file:write(contents)
  file:close()
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/CatA/SubD", "p")
vim.fn.mkdir(dir .. "/CatB", "p")

write_file(dir .. "/CatA/SubD/deep.json", vim.json.encode({ name = "Deep One", steps = {} }))
write_file(dir .. "/CatB/top.json", vim.json.encode({ name = "Top One", steps = {} }))

config.setup({ sources = { { name = "Src", path = dir } }, default_source = "Src" })

-- Record what vim.ui.open is asked to open instead of spawning a file manager.
local opened = {}
local orig_open = vim.ui.open
vim.ui.open = function(path)
  table.insert(opened, path)
end

meerkat.open()

local function norm(p)
  return ((p or ""):gsub("/", "\\")):lower()
end

local function send(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "m", false)
end

-- Step 1: cursor starts on the "SubD/" folder (CatA sorted first) -> <C-o> opens it.
send("<C-o>")
vim.defer_fn(function()
  assert(#opened == 1, "Expected one open request, got " .. #opened)
  assert(norm(opened[1]) == norm(dir .. "/CatA/SubD"), "Folder open should point at CatA/SubD, got: " .. opened[1])
  print("PASS: <C-o> on folder opens its directory")

  -- Step 2: enter the folder, highlight "Deep One" workflow -> <C-o> opens its dir.
  send("<CR>")
  vim.defer_fn(function()
    send("<C-o>")
    vim.defer_fn(function()
      assert(#opened == 2, "Expected two open requests total")
      assert(norm(opened[2]) == norm(dir .. "/CatA/SubD"), "Workflow open should point at CatA/SubD, got: " .. opened[2])
      print("PASS: <C-o> on workflow opens its directory")

      -- Step 3: switch to CatB, highlight "Top One" -> <C-o> opens CatB.
      send("<Esc>")
      vim.defer_fn(function()
        send("<Tab>")
        vim.defer_fn(function()
          send("<C-o>")
          vim.defer_fn(function()
            assert(#opened == 3, "Expected three open requests total")
            assert(norm(opened[3]) == norm(dir .. "/CatB"), "Top-level workflow open should point at CatB, got: " .. opened[3])
            print("PASS: <C-o> on top-level workflow opens its category folder")

            vim.ui.open = orig_open
            vim.fn.delete(dir, "rf")
            print("ALL OPEN_DIR TESTS PASSED!")
            vim.cmd("qall!")
          end, 60)
        end, 60)
      end, 60)
    end, 60)
  end, 60)
end, 60)