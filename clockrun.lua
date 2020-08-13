local m = require "mqtt_w"
local rate = require 'rate'
local broadcast = require '_data'.broadcast
local ok, ds18b20 = pcall(require,'ds18b20')

local week = rate:new({size=24 + 1})
local hour = rate:new({size=121, every=60, overflow=week, post="tick_min", div=60})
local minute = rate:new({size=61, every=30, overflow=hour, post="tick_now", div=2})

local last_temp 

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
local skip = 10

--local hourlog = file.open("hour.log", "a+")

local hourtime = 1200

local function edge(level, when, evts)
  local now = tmr.now()
  local sec, usec = rtctime.get()

  usec = usec - bit.band(now - when, 0x7fffffff)
  sec = sec + (usec / 1000000)

  if sec < 1000000000 then
    return
  end

  if sec > msg.last + 1 then
    if msg.last > 0 and skip < 0 then
      local s = string.format('{"at":%.6f,"edge":[%s]}', msg.at, table.concat(msg.edge, ','))
      m.send("tick", s)
    end
    msg.at = sec
    msg.edge = {}

    if skip < 0 then
      minute:push(sec)

      broadcast()
      hourtime = hourtime - 1
      if hourtime <= 0 then
        hourtime = 300
        local temp
        if last_temp then
          temp = last_temp.temp
        end

        local therate = hour:estimate()
        local msg = sjson.encode({at=msg.at, hour=therate, hour_ppm=(therate - 1) * 1000000, temp=temp})

        --hourlog:writeline(msg)
        --hourlog:flush()
        m.send("processed/data", msg)
      end
    end
  end

  msg.last = sec
  if skip < 0 then
    table.insert(msg.edge, string.format("%.6f", sec - msg.at))
  else
    skip = skip - 1
  end
end

gpio.mode(2, gpio.INT)
gpio.mode(1, gpio.INT)
gpio.trig(1, "up", debounce(edge, 1))
gpio.trig(2, "down", debounce(edge, 0))

local sec, usec = rtctime.get()
m.send("boot", string.format('{"booted":%.6f}', sec + usec / 1000000))

function getstats() 
  return {now=minute:now(), last=minute:last(), minute=minute:estimate(), hour=hour:estimate()}
end

function gethistory(which) 
  if which == "minute" then
    return {now=minute:now(), minute=minute:getHistory()}
  elseif which == "hour" then
    return {now=hour:now(), hour=hour:getHistory(30)}
  else
    return {now=week:now(), week=week:getHistory(1800)}
  end
end

function initiateTemperatureRead() 
  ds18b20:read_temp(function (result) 
    local addr, temp = next(result)
    if last_temp then
      temp = (temp + last_temp.temp * 9) / 10
    end
    local secs, usecs = rtctime.get()
    last_temp = {temp=temp, at=secs + usecs / 1000000}
    local data = sjson.encode(last_temp)
    m.send("temp", data)
    broadcast(data)
  end, nil, ds18b20.F)
end

pcall(initiateTemperatureRead)

tmr.create():alarm(30 * 1000, tmr.ALARM_AUTO, function()
  pcall(initiateTemperatureRead)
end)

m.subscribe('outside/pressure', function (topic, message) 
  local secs, usecs = rtctime.get()
  broadcast(sjson.encode({at=secs + usecs / 1000000, pressure=0 + message}))
end)

