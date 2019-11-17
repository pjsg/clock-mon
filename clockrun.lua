local m = require "mqtt_w"

local function debounce(cb)
  local timeout = tmr.create()
  local enabled = true
  timeout:register(100, tmr.ALARM_SEMI, function() enabled = true end)
  return function(level, when)
    if enabled then
      enabled = false
      cb(level, when)
      timeout:start()
    end
  end
end

local ticknumber = 0
local prevat = 0

local rate = 0.01
local extra = 0.01

local function valid(new, old) 
  local diff = new - old
  local ticks = math.floor(diff/2 + 0.5)

  local mid = old + 2 * ticks
  local max = mid + diff * rate + extra
  local min = mid - diff * rate - extra

  return min < new and new < max
end


local function edge(when)
  local now = tmr.now()
  local sec, usec = rtctime.get()

  usec = usec - bit.band(now - when, 0x7fffffff)
  sec = sec + (usec / 1000000)

  if valid(sec, prevat) then
    prevat = sec
    ticknumber = ticknumber + 1
    m.send({tick=ticknumber, at=sec}) 
  end
end

gpio.mode(2, gpio.INT)
gpio.trig(2, "down", debounce(function(level, when) edge(when) end))


