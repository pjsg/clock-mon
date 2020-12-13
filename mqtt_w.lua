-- mqtt
--
local M = {}

local m = mqtt.Client(string.format("clockmon-%06x", node.chipid()))

local connected = false

local topic = string.format("/grandfather/%06x/", node.chipid())

local queue = {}

m:on("connect", function() connected = true print('MQTT Connected') end)
m:on("offline", function() connected = false print ('MQTT Disconnected') end)

local subscriptions = {}

function handleMessage(client, topic, message)
  local cb = subscriptions[topic]
  if cb then
    cb(topic, message)
  end
end

m:on("message", handleMessage)

function M.subscribe(topic, cb) 
  subscriptions[topic] = cb
  m:subscribe(topic, 0)
end

function M.connect() 
  m:connect("saturn.gladstonefamily.net", 1883)
end

function M.send(t, o)
  local msg = o
  if type(msg) ~= "string" then
    msg = sjson.encode(o)
  end
  print("Sending", msg)
  local sent = false
  if connected then
    while queue[1] ~= nil do
      collectgarbage()
      sent = m:publish(topic .. queue[1].t, queue[1].m, 1, 0)
      if not sent then
        break
      end
      print ('Sent', queue[1])
      table.remove(queue, 1)
    end
    collectgarbage()
    sent = m:publish(topic .. t, msg, 1, 0)
  end
  if not sent then
    print ('Queueing', msg)
    table.insert(queue, {t=t, m=msg})
    if #queue > 10 then
      queue = {}
      print ('Flushed queue')
    end
  end
end

return M
