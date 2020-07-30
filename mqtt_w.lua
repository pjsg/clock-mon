-- mqtt
--
local M = {}

local m = mqtt.Client("grandfather")

local connected = false

local queue = {}

m:on("connect", function() connected = true print('MQTT Connected') end)
m:on("offline", function() connected = false print ('MQTT Disconnected') end)

function M.connect() 
  m:connect("neptune.gladstonefamily.net", 1883)
end

function M.send(o)
  local msg = o
  if type(msg) ~= "string" then
    msg = sjson.encode(o)
  end
  print("Sending", msg)
  local sent = false
  if connected then
    while queue[1] ~= nil do
      collectgarbage()
      sent = m:publish("/grandfather", queue[1], 1, 0)
      if not sent then
        break
      end
      print ('Sent', queue[1])
      table.remove(queue, 1)
    end
    collectgarbage()
    sent = m:publish("/grandfather", msg, 1, 0)
  end
  if not sent then
    print ('Queueing', msg)
    table.insert(queue, msg)
    if #queue > 10 then
      queue = {}
      print ('Flushed queue')
    end
  end
end

return M
