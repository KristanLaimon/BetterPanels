#!/usr/bin/env lua
--- Runs every `_spec.lua` file under `tests/spec/` with `PanelsPlusTestFramework`.
---
--- No external dependencies (no busted, no luarocks) -- just plain Lua 5.4.
--- Usage: `lua tests/run_tests.lua`, invoked from the plugin's repo root.

local script_dir = arg[0]:match("(.*/)") or "./"
local repo_root = script_dir .. "../"

package.path = repo_root .. "?.lua;" .. repo_root .. "?/init.lua;" .. package.path

require("tests.spec.helper")

local spec_modules = {
    "tests.spec.panelviewer_gotoviewrel_spec",
    "tests.spec.native_panel_zoom_spec",
    "tests.spec.memory_spec",
    "tests.spec.embedded_image_spec",
    "tests.spec.nativedetector_spec",
    "tests.spec.panelviewer_reader_gesture_spec",
    "tests.spec.viewer_controller_rotation_spec",
    "tests.spec.panelviewer_leftedge_spec",
    "tests.spec.panelviewer_tapnav_spec",
    "tests.spec.panelviewer_transform_spec",
    "tests.spec.panelviewer_margin_spec",
    "tests.spec.panelviewer_highlight_spec",
    "tests.spec.panelviewer_refineword_spec",
    "tests.spec.ocrdebug_spec",
    "tests.spec.ocrdebug_report_spec",
    "tests.spec.geometry_spec",
    "tests.spec.panelviewport_spec",
    "tests.spec.wordfinder_spec",
    "tests.spec.pagebitmap_spec",
    "tests.spec.segmenter_spec",
    "tests.spec.panelviewer_navtransition_spec",
    "tests.spec.dataset_benchmark_spec",
}

for _, mod in ipairs(spec_modules) do
    print("\n== " .. mod .. " ==")
    require(mod)
end

local framework = require("tests.PanelsPlusTestFramework")
local all_passed = framework.summary()
os.exit(all_passed and 0 or 1)
