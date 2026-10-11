local M = {}

--- Returns the 0-based positions of every character of `query` found in
--- `text` as a subsequence (case-insensitive), or nil when there is no match.
--- An empty query always matches and yields an empty position list.
local function fuzzy_positions(text, query)
  text = text or ""
  query = query or ""

  if query == "" then
    return {}
  end

  local lower_text = text:lower()
  local lower_query = query:lower()
  local positions = {}
  local search_from = 1

  for i = 1, #lower_query do
    local char = lower_query:sub(i, i)
    local found = lower_text:find(char, search_from, true)

    if not found then
      return nil
    end

    positions[#positions + 1] = found - 1
    search_from = found + 1
  end

  return positions
end

--- Returns the 0-based positions of a contiguous `query` inside `text`
--- (case-insensitive), or nil when the query is not found as a substring.
local function substring_positions(text, query)
  text = text or ""
  query = query or ""

  if query == "" then
    return nil
  end

  local start = text:lower():find(query:lower(), 1, true)

  if not start then
    return nil
  end

  local positions = {}

  for i = 0, #query - 1 do
    positions[#positions + 1] = start - 1 + i
  end

  return positions
end

--- Case-insensitive subsequence fuzzy match.
--- Returns true when every character in `query` appears, in order, in `text`.
function M.fuzzy_match(text, query)
  return fuzzy_positions(text, query) ~= nil
end

--- Builds the searchable representation of a workflow.
--- Returns a table with the original workflow, its display name/description,
--- a `cat_path` such as "Stats/Test" and a `search_string` combining all
--- searchable fields.
function M.index_workflow(workflow)
  workflow = workflow or {}

  local category = workflow.category or "General"
  local subcategory = workflow.subcategory

  local cat_path = category

  if subcategory and subcategory ~= "" then
    cat_path = category .. "/" .. subcategory
  end

  local name = workflow.name or ""
  local description = workflow.description or ""
  local source = workflow.source or ""

  local search_string =
    string.format("[%s] %s %s %s", cat_path, name, description, source)

  return {
    workflow = workflow,
    name = name,
    description = description,
    cat_path = cat_path,
    source = source,
    search_string = search_string,
  }
end

--- Filters and ranks indexed workflows against `query`.
--- Returns a list of `{ item = indexed, positions = { 0-based name offsets } }`
--- ordered from best to worst match. `positions` is always relative to the
--- workflow name so callers can highlight matched characters directly.
function M.filter(items, query)
  query = query or ""
  local results = {}

  for _, item in ipairs(items) do
    if query == "" then
      results[#results + 1] = { item = item, positions = {}, score = 0 }
    else
      local name = item.name or ""
      local search_string = item.search_string or name
      local positions = substring_positions(name, query)
      local score

      if positions then
        -- Contiguous match in the name: best, favour earlier matches.
        score = 3000 - positions[1]
      else
        positions = fuzzy_positions(name, query)

        if positions then
          -- Subsequence match in the name: prefer tighter matches.
          local spread = (positions[#positions] - positions[1]) + 1
          score = 2000 - spread
        else
          -- Fall back to matching category/description only. Do not highlight
          -- the name for these, since positions would not line up with it.
          if substring_positions(search_string, query) then
            score = 1000
          elseif fuzzy_positions(search_string, query) then
            score = 500
          end

          positions = {}
        end
      end

      if score then
        results[#results + 1] = {
          item = item,
          positions = positions,
          score = score,
        }
      end
    end
  end

  table.sort(results, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end

    return (a.item.name or ""):lower() < (b.item.name or ""):lower()
  end)

  return results
end

return M
