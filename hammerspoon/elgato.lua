-- https://vk.cc/cHsPIz

elgato = {
  _lights = {}
}


function elgato:update()
  local browser = hs.bonjour.new()
  local SERVICE_TYPE = "_elg._tcp."
  browser:findServices(SERVICE_TYPE, function(
    browserObject,
    domain,
    isAdvertised,
    serviceObject,
    isMoreExpected
  )
    if domain == "error" then
      return
    end
    local serviceType = serviceObject:type()
    if serviceType ~= SERVICE_TYPE then
      return
    end

    local name = serviceObject:name()
    if isAdvertised == false then
      self._lights[name] = nil
      return
    end

    if not self._lights[name] then
      self._lights[name] = {
        object = serviceObject,
        resolved = false,
        address = nil,
        port = nil,
      }
    end
    if self._lights[name].resolved then
      return
    end

    local timeoutSec = 5
    serviceObject:resolve(timeoutSec, function(userdata, result)
      if result ~= "resolved" then
        return
      end
      for _, info in pairs(self._lights) do
        if not info.resolved then
          info.address = info.object:addresses()[1]
          info.port = info.object:port()
          if info.address and info.port then
            info.resolved = true
          end
        end
      end
    end)
  end)
end


function elgato:_switchOne(address, port, isOn)
  local url = "http://" .. address .. ":" .. port .. "/elgato/lights"
  local headers = nil
  -- KeyLights are very slow to response for HTTP requests after they
  -- were not active for some time.
  hs.http.asyncGet(url, headers, function(resCode, body, headers)
    if resCode < 200 or resCode >= 300 then
      return
    end

    local settings = hs.json.decode(body)
    if not settings then
      return
    end

    if isOn then
      settings.lights[1].on = 1
    else
      settings.lights[1].on = 0
    end

    local data = hs.json.encode(settings)
    hs.http.asyncPut(url, data, headers, function() end)
  end)
end


function elgato:switch(isOn)
  for _, info in pairs(self._lights) do
    if info.resolved then
      self:_switchOne(info.address, info.port, isOn)
    end
  end
end


function elgato:lightsCount()
  local result = 0
  for _, info in pairs(self._lights) do
    if (info.resolved) then
      result = result + 1
    end
  end
  return result
end
