local LX_Test = {}

-----------------------------------------------------------
-- Test Framework
-----------------------------------------------------------
local test_results = {
    passed = 0,
    failed = 0,
    total_passed = 0,
    total_failed = 0
}

local log_lines = {}

local function log_to_file(text)
    table.insert(log_lines, text)
end

local function write_log_file()
    local filename = "LX_Test.log"
    local content = "[LX_Test] Log\n"
    content = content .. string.rep("-", 50) .. "\n\n"
    for _, line in ipairs(log_lines) do
        content = content .. line .. "\n"
    end

    if core.create_log_file then
        core.create_log_file(filename)
    end
    if core.write_log_file then
        core.write_log_file(filename, content)
        core.log("[LX_Test] Results written to scripts_log/" .. filename)
    else
        core.log_error("[LX_Test] core.write_log_file not available")
    end
end

local function test(name, condition, message)
    if condition then
        test_results.passed = test_results.passed + 1
        test_results.total_passed = test_results.total_passed + 1
        -- Only log to file, not console (reduces noise)
        log_to_file("[PASS] " .. name)
    else
        test_results.failed = test_results.failed + 1
        test_results.total_failed = test_results.total_failed + 1
        local msg = "[FAIL] " .. name .. " - " .. (message or "")
        -- Log failures to console so they're visible
        core.log_error(msg)
        log_to_file(msg)
    end
end

local function run_tests(name, test_fn)
    -- Only log to file, not console
    log_to_file("\n--- " .. name .. " ---")
    test_results.passed = 0
    test_results.failed = 0

    local success, err = pcall(test_fn)
    if not success then
        core.log_error("[LX_Test] Error: " .. tostring(err))
        log_to_file("[LX_Test] Error: " .. tostring(err))
    end
end

-----------------------------------------------------------
-- Deferred Tests (wait for LX_UI)
-----------------------------------------------------------
local tests_ran = false

local function run_all_tests()
    if tests_ran then return end

    local LX_UI = _G.LX_UI
    if not LX_UI then return end

    tests_ran = true

    run_tests("Core", function()
        test("Library loaded", LX_UI ~= nil)
        test("VERSION", LX_UI.VERSION == "1.0.0")
        test("constants", LX_UI.constants ~= nil)
        test("helpers", LX_UI.helpers ~= nil)
        test("Input", LX_UI.Input ~= nil)
        test("Rendering", LX_UI.Rendering ~= nil)
        test("BaseComponent", LX_UI.BaseComponent ~= nil)
        test("Menu", LX_UI.Menu ~= nil)
        test("Colors", LX_UI.Colors ~= nil)
        test("Settings", LX_UI.Settings ~= nil)
    end)

    run_tests("Components", function()
        test("Label", LX_UI.Label ~= nil)
        test("Separator", LX_UI.Separator ~= nil)
        test("Header", LX_UI.Header ~= nil)
        test("Checkbox", LX_UI.Checkbox ~= nil)
        test("Slider", LX_UI.Slider ~= nil)
        test("Button", LX_UI.Button ~= nil)
        test("ProgressBar", LX_UI.ProgressBar ~= nil)
        test("TextInput", LX_UI.TextInput ~= nil)
        test("Combobox", LX_UI.Combobox ~= nil)
        test("Keybind", LX_UI.Keybind ~= nil)
        test("ColorPicker", LX_UI.ColorPicker ~= nil)
        test("TreeNode", LX_UI.TreeNode ~= nil)
        test("Listbox", LX_UI.Listbox ~= nil)
    end)

    run_tests("Helpers", function()
        local h = LX_UI.helpers
        test("clamp min", h.clamp(-5, 0, 10) == 0)
        test("clamp max", h.clamp(15, 0, 10) == 10)
        test("lerp", h.lerp(0, 100, 0.5) == 50)
        test("point_in_rect true", h.point_in_rect(50, 50, 0, 0, 100, 100))
        test("point_in_rect false", not h.point_in_rect(150, 50, 0, 0, 100, 100))
        test("generate_id unique", h.generate_id() ~= h.generate_id())
    end)

    run_tests("Menu", function()
        local menu = LX_UI.Menu:new("Test", 300, 400, "test")
        test("created", menu ~= nil)
        test("title", menu.title == "Test")
        test("width", menu.width == 300)
        test("add_component", type(menu.add_component) == "function")
        test("render", type(menu.render) == "function")
        test("update", type(menu.update) == "function")
    end)

    run_tests("Menu Add Methods", function()
        local menu = LX_UI.Menu:new("Test2", 300, 400, "test2")
        test("add_label", type(menu.add_label) == "function")
        test("add_checkbox", type(menu.add_checkbox) == "function")
        test("add_slider", type(menu.add_slider) == "function")
        test("add_button", type(menu.add_button) == "function")
        test("add_combobox", type(menu.add_combobox) == "function")
        test("add_colorpicker", type(menu.add_colorpicker) == "function")
        test("add_listbox", type(menu.add_listbox) == "function")
    end)

    run_tests("Component Creation", function()
        local menu = LX_UI.Menu:new("Test3", 300, 400, "test3")
        test("Label", menu:add_label("Test") ~= nil)
        test("Separator", menu:add_separator() ~= nil)
        test("Header", menu:add_header("Section") ~= nil)
        test("Checkbox", menu:add_checkbox("Enable", nil, nil, true) ~= nil)
        test("Slider", menu:add_slider("Vol", nil, nil, 0, 100, 50) ~= nil)
        test("Button", menu:add_button("Click", nil, nil, 100, 25) ~= nil)
        test("ProgressBar", menu:add_progressbar("Load", nil, nil, 75, 100) ~= nil)
        test("TextInput", menu:add_textinput("Name", nil, nil, "default") ~= nil)
        test("Combobox", menu:add_combobox("Opt", nil, nil, {"A","B"}, 1) ~= nil)
        test("Keybind", menu:add_keybind("Key", nil, nil, 0x41) ~= nil)
        test("ColorPicker", menu:add_colorpicker("Col", nil, nil, {r=255,g=0,b=0,a=255}) ~= nil)
        test("TreeNode", menu:add_treenode("Node", nil, nil, false) ~= nil)
        test("Listbox", menu:add_listbox("List", nil, nil, {"A","B"}, 1) ~= nil)
        test("13 components", #menu.component_order == 13)
    end)

    run_tests("Component Methods", function()
        local cb = LX_UI.Checkbox:new({default = false})
        test("Checkbox get_value", cb:get_value() == false)
        cb:toggle()
        test("Checkbox toggle", cb:get_value() == true)

        local slider = LX_UI.Slider:new({min = 0, max = 100, default = 50})
        test("Slider get_value", slider:get_value() == 50)
        slider:set_value(150)
        test("Slider clamp", slider:get_value() == 100)

        local combo = LX_UI.Combobox:new({items = {"A", "B"}, default = 1})
        test("Combobox get_selected_text", combo:get_selected_text() == "A")

        local tree = LX_UI.TreeNode:new({default = false})
        tree:expand()
        test("TreeNode expand", tree:get_value() == true)

        local list = LX_UI.Listbox:new({items = {"A", "B"}, default = 1})
        list:add_item("C")
        test("Listbox add_item", #list.items == 3)
    end)

    local summary = "[LX_Test] TOTAL: " .. test_results.total_passed .. " passed, " .. test_results.total_failed .. " failed"
    core.log(summary)
    log_to_file("\n" .. string.rep("-", 50))
    log_to_file(summary)

    write_log_file()
end

-- Run on first update tick (all plugins loaded by then)
core.register_on_update_callback(run_all_tests)

return LX_Test
