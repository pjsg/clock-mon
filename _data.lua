
return function (socket)
  local t = tmr.create()
  local function dosend()
    if socket.getPendingCount() < 2 then
      pcall(function() socket.send(sjson.encode({stats=getstats()}), 1) end)
    end
  end
  t:alarm(2000, tmr.ALARM_AUTO, dosend)
  function socket.onclose()
    t:unregister()
    t = nil
  end
  pcall(function() socket.send(sjson.encode({history=gethistory()}), 1) end)
  dosend()
end


