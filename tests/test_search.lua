local search = require("meerkat.search")

-- Test 1: Subsequence fuzzy matching
assert(search.fuzzy_match("Connect Host", "con") == true, "Should match 'con' in 'Connect Host'")
assert(search.fuzzy_match("Connect Host", "cho") == true, "Should match 'cho' in 'Connect Host'")
assert(search.fuzzy_match("Connect Host", "xyz") == false, "Should not match 'xyz' in 'Connect Host'")
print("PASS: Subsequence fuzzy match tests")

-- Test 2: Workflow indexing
local wf = {
  name = "test-01",
  category = "Stats",
  subcategory = "Test",
  description = "A test workflow",
}
local indexed = search.index_workflow(wf)
assert(indexed.cat_path == "Stats/Test", "cat_path should be Stats/Test")
assert(indexed.search_string:find("%[Stats/Test%]"), "Search string should include formatted category path")
print("PASS: Workflow indexing tests")

-- Test 3: Filtering & ranking
local all_items = {
  search.index_workflow({ name = "connect", category = "Hosts" }),
  search.index_workflow({ name = "reset-maya", category = "Helpdesk" }),
  search.index_workflow({ name = "system-stats", category = "Stats" }),
}

local matches = search.filter(all_items, "may")
assert(#matches >= 1, "Should find at least 1 match for 'may'")
assert(matches[1].item.workflow.name == "reset-maya", "Top match should be reset-maya")
assert(type(matches[1].positions) == "table", "Should return match positions")
print("PASS: Search filtering tests")

print("ALL SEARCH TESTS PASSED!")
