dir = function (o) for k, v in pairs(o) do print(k, "=>", v) end end
idir = function (o) for i, v in ipairs(o) do print(i, "~>", v) end end
cls = hs.console.clearConsole
