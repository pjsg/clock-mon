-- mqtt
--
local M = {}

local m = mqtt.Client("grandfather")

local connected = false

m:on("connect", function() connected = true end)
m:on("offline", function() connected = false end)

m:connect("neptune.gladstonefamily.net", 1883)

function M.send(o)
  print("Sending", sjson.encode(o))
  if connected then
    m:publish("/grandfather", sjson.encode(o), 0, 0)
  end
end

return M
