local sockets = {}

local M = {}

M.serve = function (socket)
  function socket.onclose()
    sockets[socket] = nil
  end
  socket.send(sjson.encode({history=gethistory('minute')}), 1)
  tmr.create():alarm(500, tmr.ALARM_SINGLE, function()
    socket.send(sjson.encode({history=gethistory('hour')}), 1)
  end)
  tmr.create():alarm(1500, tmr.ALARM_SINGLE, function()
    socket.send(sjson.encode({history=gethistory('week')}), 1)
  end)
  sockets[socket] = 1
end

M.broadcast = function(msg)
  local data = sjson.encode({stats=getstats()})
  for k, v in pairs(sockets) do
    pcall(function() k.send(data, 1) end)
  end
end


return M

