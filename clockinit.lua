local config = require "config"("config")
local m = require "mqtt_w"
local broadcast = require '_data'.broadcast

lastNtpResult = {}

local function printrtc()
  local _, _, rate = rtctime.get()
  print ('rate', rate)
end

local ok, clock_data = pcall(sjson.decode, file.getcontents("clock.data"))
local boottime

function getboottime()
  return boottime
end

if not ok then
  clock_data = nil
end
if clock_data then
  rtctime.set(nil, nil, clock_data.rate)
end

local ntplog = file.open("ntp.log", "a+")

local function startsync(cb)
    sntp.sync({"192.168.1.20", "192.168.1.21", "0.nodemcu.pool.ntp.org", "1.nodemcu.pool.ntp.org", "2.nodemcu.pool.ntp.org"
    }, function (a,b, c, d ) 
      lastNtpResult = { secs=a, usecs=b, server=c, info=d }
      print(a,b, c, d['offset_us']) printrtc() 
      if not boottime then
        boottime = a + b / 1000000
      end
      local msg = {ntp=lastNtpResult}
      local _, _, rate = rtctime.get()
      file.putcontents("clock.data", sjson.encode({rate=rate}))
      local logmsg = sjson.encode({at=a + b / 1000000, rate=rate, ntp=lastNtpResult})
      m.send(logmsg)
      ntplog:writeline(logmsg)
      ntplog:flush()
      broadcast(logmsg)
      cb()
    end, function(e) print (e) end, 1)
end

local function doOnce(cb)
  local done = false
  return function ()
    if not done then
      cb()
      done = true
    end
  end
end

syslog = (require "syslog")(config.syslog_("192.168.1.68"))

-- node.egc.setmode(node.egc.ON_ALLOC_FAILURE)

if true then
  dprint = function() end
else
  dprint = print
end

local t0 = tmr.create()

t0:alarm(1000, tmr.ALARM_AUTO, function(t)
   local ip = wifi.sta.getip()
   if ip == nil then
     print ("no ip")
     return
   end
   print ("got ip")
   t:unregister()
   m.connect()
   syslog:send("Booted: " .. sjson.encode({node.bootreason()}))
   node.setcpufreq(node.CPU160MHZ)
   startsync(doOnce(function() require("clockrun") end))
   mdns.register(string.format("grandfather-%06x", node.chipid()), { service="http", port=80 })
   local adder = require("httpserver")
   require("webserver").register(adder)
   adder("GET", "/data", function (c, args, req) 
     require "httpserver-websocket"(c, req)
   end)
end)

