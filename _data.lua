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
  tmr.create():alarm(2500, tmr.ALARM_SINGLE, function()
    socket.send(sjson.encode({boottime=getboottime()}), 1)
  end)
  sockets[socket] = 1
end

M.broadcast = function(msg)
  if not msg then
    msg = {stats=getstats()}
  end
  if type(msg) ~= "string" then
    msg = sjson.encode(msg)
  end
  for k, v in pairs(sockets) do
    pcall(function() k.send(msg, 1) end)
  end
end


return M

