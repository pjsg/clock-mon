local m = require "mqtt_w"

local function debounce(cb, level)
  local last = 0
  return function(levelx, when, evts)
    if bit.band(when - last, 0xffffff) > 40000 then
      -- Get this out of the initial callback -- must not spend too long here
      node.task.post(node.task.MEDIUM_PRIORITY, function () cb(level, when, evts) end)
    end
    last = when
  end
end

local msg = {last=0}

local function edge(level, when, evts)
  local now = tmr.now()
  local sec, usec = rtctime.get()

  --if evts > 1 then
    --print("Multiple events", evts, "at", when, "for", level)
  --end

  usec = usec - bit.band(now - when, 0x7fffffff)
  sec = sec + (usec / 1000000)

  if sec < 1000000000 then
    return
  end

  if sec > msg.last + 1 then
    if msg.last > 0 then
      local s = string.format('{"at":%.6f,"edge":[%s]}', msg.at, table.concat(msg.edge, ','))
      m.send(s)
    end
    msg.at = sec
    msg.edge = {}
    -- msg.off = {}
  end

  msg.last = sec
  table.insert(msg.edge, string.format("%.6f", sec - msg.at))
  -- if level == gpio.HIGH then
  --   table.insert(msg.on, sec - msg.at)
  -- else
  --   table.insert(msg.off, sec - msg.at)
  -- end
end

gpio.mode(2, gpio.INT)
gpio.mode(1, gpio.INT)
gpio.trig(1, "up", debounce(edge, 1))
gpio.trig(2, "down", debounce(edge, 0))

local sec, usec = rtctime.get()
m.send(string.format('{"booted":%.6f}', sec + usec / 1000000))



