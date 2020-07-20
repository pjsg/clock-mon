local config = require "config"("config")
local m = require "mqtt_w"

lastNtpResult = {}

local function printrtc()
  local _, _, rate = rtctime.get()
  print ('rate', rate)
end

local function startsync(cb)
    sntp.sync({"192.168.1.21", "0.nodemcu.pool.ntp.org", "1.nodemcu.pool.ntp.org", "2.nodemcu.pool.ntp.org"
    }, function (a,b, c, d ) 
      lastNtpResult = { secs=a, usecs=b, server=c, info=d }
      print(a,b, c, d['offset_us']) printrtc() 
      m.send({ntp=lastNtpResult})
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

