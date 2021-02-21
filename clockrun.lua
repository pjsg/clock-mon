local config = require "config"("config")
local m = require "mqtt_w"
local rate = require 'rate'
local broadcast = require '_data'.broadcast
local ok, ds18b20 = pcall(require,'ds18b20')

local pendulum_period = config.pendulum_period_(2)

local ticks_per_minute = math.round(60 / pendulum_period)
local minutes_per_hour = math.round(3600 / pendulum_period) / ticks_per_minute

local hour = {left=rate:new({size=2 * minutes_per_hour + 1, every=minutes_per_hour, post="tick_min", div=minutes_per_hour}),
              speed=rate:new({size=minutes_per_hour + 1, every=minutes_per_hour})}
local minute = {left=rate:new({size=ticks_per_minute * 2 + 1, every=ticks_per_minute, overflow=hour.left, post="tick_now", div=pendulum_period}),
                speed=rate:new({size=ticks_per_minute + 1, every=ticks_per_minute, overflow=hour.speed})}

local last_temp 
local last_pressure 

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

local function bind_pin(cb, side)
  local last = 0
  return function(levelx, when, evts)
    if bit.band(when - last, 0xffffff) > 40000 then
      -- Get this out of the initial callback -- must not spend too long here
      node.task.post(node.task.MEDIUM_PRIORITY, function () cb(when, evts, side) end)
    end
    last = when
  end
end

local msg = {last=0}
local skip = 10

--local hourlog = file.open("hour.log", "a+")

local hourtime = 1200

local function edge(when, evts, side)
  local now = tmr.now()
  local sec, usec = rtctime.get()

  usec = usec - bit.band(now - when, 0x7fffffff)
  sec = sec + (usec / 1000000)

  if sec < 1000000000 then
    return
  end

  if msg.last_side and msg.last_side ~= side then
    local speed = 41.66/(sec - msg.last_side_time)
    minute.speed:push(speed)
    msg.last_speed = speed
  end
  msg.last_side = side
  msg.last_side_time = sec

  if side == 'left' then
    if sec > msg.last + pendulum_period / 2 then
      if msg.last > 0 and skip < 0 then
	local s = sjson.encode({at=msg.at,edge=msg.edge, speed=msg.last_speed})
	m.send("tick", s)
	msg.last_speed = nil
      end
      msg.at = sec
      msg.edge = {}

      if skip < 0 then
	minute.left:push(sec)

	broadcast()
	hourtime = hourtime - 1
	if hourtime <= 0 then
	  hourtime = 300
	  local pressure
	  if last_pressure then
	    pressure = last_pressure.pressure
	  end

	  local temp
	  if last_temp then
	    temp = last_temp.temp
	  end

	  local therate = hour.left:estimate()
	  local msg = sjson.encode({at=msg.at, hour=therate, hour_ppm=(1 - therate) * 1000000, temp=temp, pressure=pressure, speed=hour.speed:estimate()})

	  m.send("processed/data", msg)
	end
      end
    end

    msg.last = sec

    if skip < 0 then
      table.insert(msg.edge, sec - msg.at)
    else
      skip = skip - 1
    end
  end
end

gpio.mode(2, gpio.INT)
gpio.mode(1, gpio.INT)
gpio.trig(1, "down", bind_pin(edge, 'left'))
gpio.trig(2, "down", bind_pin(edge, 'right'))

local sec, usec = rtctime.get()
m.send("boot", sjson.encode({booted=sec + usec / 1000000, reason={node.bootreason()}}))

function getstats() 
  return {now=minute.left:now(), last=minute.left:last(), minute=minute.left:estimate(), hour=hour.left:estimate()}
end

function gethistory(which) 
  if which == "minute" then
    return {now=minute.left:now(), minute=minute.left:getHistory()}
  else
    return {now=hour.left:now(), hour=hour.left:getHistory(30)}
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

function tohex(str)
    return (str:gsub('.', function (c)
        return string.format('%02X', string.byte(c))
    end))
end

function read_spl(reg_addr, len)
    i2c.start(0)
    i2c.address(0, 0x77, i2c.TRANSMITTER)
    i2c.write(0, reg_addr)
    i2c.stop(0)
    i2c.start(0)
    i2c.address(0, 0x77, i2c.RECEIVER)
    c = i2c.read(0, len)
    i2c.stop(0)
    return c
end


function write_spl(reg_addr, data)
    i2c.start(0)
    i2c.address(0, 0x77, i2c.TRANSMITTER)
    i2c.write(0, reg_addr)
    c = i2c.write(0, data)
    i2c.stop(0)
    return c
end

local spl_cal
local coef

function get_cal(data, start, len, unsigned)
  local result = 0

  local lenc = len 
  local offset = 1 + (start >> 3)
  local offbit = start & 7
  lenc = lenc + offbit

  while lenc > 0 do
    result = (result << 8) + string.byte(data, offset)
    lenc = lenc - 8
    offset = offset + 1
  end

  if lenc < 0 then
    result = result >> (-lenc)
  end

  result = result & ((1 << len) - 1)

  if not unsigned then
    if (result >> (len - 1)) > 0 then
      result = result - (1 << len)
    end
  end

  return result
end

function doTemperatureRead() 
  if not spl_cal then
    assert(string.byte(read_spl(0x0d, 1)) == 0x10)
    write_spl(0x06, 0x06)
    write_spl(0x07, 0x86)
    write_spl(0x09, 0x0C)
    spl_cal = read_spl(6, 4)
    local coefdata = read_spl(16, 18)
    coef = {}
    coef.c0 = get_cal(coefdata, 0, 12)
    coef.c1 = get_cal(coefdata, 12, 12)
    coef.c00 = get_cal(coefdata, 24, 20)
    coef.c10 = get_cal(coefdata, 44, 20)
    coef.c01 = get_cal(coefdata, 64, 16)
    coef.c11 = get_cal(coefdata, 80, 16)
    coef.c20 = get_cal(coefdata, 96, 16)
    coef.c21 = get_cal(coefdata, 112, 16)
    coef.c30 = get_cal(coefdata, 128, 16)
    print(sjson.encode(coef))
  end
  write_spl(0x08, 0x02)  -- read temperature
  tmr.create():alarm(300, tmr.ALARM_SINGLE, function (t) 
    local raw = read_spl(3, 3)
    local tmp = get_cal(raw, 0, 24)
    local traw = tmp / 1040384.0
    local tcomp = coef.c0 * 0.5 + coef.c1 * traw

    local secs, usecs = rtctime.get()
    local temp = {temp=tcomp * 9 / 5 + 32, at=secs + usecs / 1000000}
    local data = sjson.encode(temp)
    m.send("temp", data)
    broadcast(data)
    
    write_spl(0x08, 0x01) -- read pressure
    t:alarm(300, tmr.ALARM_SINGLE, function (t)
      local raw = read_spl(0, 3)
      local prs = get_cal(raw, 0, 24)
      local praw = prs / 1040384.0
      local pcomp = coef.c00 + praw * (coef.c10 + praw * (coef.c20 + praw * coef.c30)) + traw * coef.c01 + traw * praw  * (coef.c11 + praw * coef.c21)
      local secs, usecs = rtctime.get()
      last_pressure = {at=secs + usecs / 1000000, pressure=pcomp / 3386.4}
      local data = sjson.encode(last_pressure)
      m.send("pressure", data)
      broadcast(data)
    end)
  end)
end


local tempFunction = doTemperatureRead
if not pcall(tempFunction) then
  tempfunction = initiateTemperatureRead
  m.subscribe('outside/pressure', function (topic, message) 
      local secs, usecs = rtctime.get()
      local data = sjson.encode({at=secs + usecs / 1000000, pressure=0 + message})
      m.send("pressure", data)
      broadcast(data)
  end)
end

tmr.create():alarm(30 * 1000, tmr.ALARM_AUTO, function()
  pcall(tempFunction)
end)

