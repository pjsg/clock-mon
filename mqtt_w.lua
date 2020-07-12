-- mqtt
--
local M = {}

local m = mqtt.Client("grandfather")

local connected = false

local queue = {}

m:on("connect", function() connected = true end)
m:on("offline", function() connected = false end)

m:connect("neptune.gladstonefamily.net", 1883)

function M.send(o)
  local msg = o
  if type(msg) ~= "string" then
    msg = sjson.encode(o)
  end
  print("Sending", msg)
  local sent = false
  if connected then
    while queue[1] ~= nil do
      sent = m:publish("/grandfather", queue[1], 1, 0)
      if not sent then
        break
      end
      print ('Sent', queue[1])
      table.remove(queue, 1)
    end
    sent = m:publish("/grandfather", msg, 1, 0)
  end
  if not sent then
    print ('Queueing', msg)
    table.insert(queue, msg)
  end
end

return M
