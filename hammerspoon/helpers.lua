dir = function (v) for k, v in pairs(v) do print(k, "=>", v) end end
idir = function (v) for i, v in ipairs(v) do print(i, "~>", v) end end
function count(v)
  local sum = 0
  for _ in pairs(v) do
    sum = sum + 1
  end
  return sum
end
cls = hs.console.clearConsole
