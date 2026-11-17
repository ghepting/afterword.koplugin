-- Shared setup for the unit tests: finds the plugin's modules and gives them stand-ins for the
-- few KOReader modules they load, so the logic runs under plain luajit.
local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$") or "."
package.path = here .. "/../../afterword.koplugin/?.lua;" .. package.path
package.preload["gettext"] = function()
    local g = setmetatable({}, { __call = function(_, s) return s end })
    g.ngettext = function(one, many, n) return n == 1 and one or many end
    return g
end
package.preload["ffi/util"] = function()
    return {
        template = function(s, ...)
            local args = { ... }
            return (s:gsub("%%(%d)", function(i) return tostring(args[tonumber(i)]) end))
        end,
    }
end
package.preload["util"] = function() return { getFriendlySize = function(n) return n .. " B" end } end

local T = {}
local failures, count = 0, 0

function T.test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if ok then
        print("  ok    " .. name)
    else
        failures = failures + 1
        print("  FAIL  " .. name .. "\n          " .. tostring(err))
    end
end

function T.eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

-- Call last: prints the totals and exits non-zero when anything failed.
function T.done()
    print(string.format("  %d tests, %d failed", count, failures))
    if failures > 0 then os.exit(1) end
end

return T
