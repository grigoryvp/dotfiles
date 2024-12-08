netstat = {}


function netstat:get(callback)
  function onExit(exitCode, stdOut, _)
    if exitCode ~= 0 then
      return nil
    end
    return {
      gateway = nil
    }
  end
  local task = hs.task.new("/usr/sbin/netstat", onExit, {"-rn"})
  task:start()
end
