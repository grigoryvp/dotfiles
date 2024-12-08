netstat = {
  _task = nil
}


function netstat:get(callback)

  assert(not self._task or not self._task:isRunning())

  function onExit(exitCode, stdOut, _)
    if exitCode ~= 0 then
      return callback(nil)
    end

    gateway = nil
    for line in stdOut:gmatch("[^\r\n]+") do
      pattern = "^default +([0-9]+%.[0-9]+%.[0-9]+%.[0-9]+) .+ en0 *$"
      _, _, match = line:find(pattern)
      if not gateway and match then
        gateway = match
      end
    end

    if not gateway then
      return callback(nil)
    end

    return callback({
      gateway = gateway
    })
  end

  self._task = hs.task.new("/usr/sbin/netstat", onExit, {"-rn"})
  self._task:start()
end


function netstat:isRunning()
  if not self._task then
    return false
  end
  return self._task:isRunning()
end
