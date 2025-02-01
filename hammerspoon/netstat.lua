-- Max amount of seconds for netstat to run (it hangs sometimes)
TIMEOUT_SEC = 5

netstat = {
  _task = nil,
  _startTimeSec = nil
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

  self._startTimeSec = hs.timer.absoluteTime() / 1000000000
  self._task = hs.task.new("/usr/sbin/netstat", onExit, {"-rn"})
  self._task:start()
end


function netstat:isRunning()
  if not self._task then
    return false
  end

  isRunning = self._task:isRunning()
  if not isRunning then
    return false
  end

  assert(type(self._startTimeSec == "number"), "integrity error")
  curTimeSec = hs.timer.absoluteTime() / 1000000000
  if curTimeSec > self._startTimeSec + TIMEOUT_SEC then
    self._task:terminate()
    -- otherwise next call to get() may receive "running"
    self._task = nil
    return false
  end

  return true
end
