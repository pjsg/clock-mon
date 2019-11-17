local config = require "config"("config")

lastNtpResult = {}

local function printrtc()
  local _, _, rate = rtctime.get()
  print ('rate', rate)
end

local function startsync()
    sntp.sync({"192.168.1.21", "0.nodemcu.pool.ntp.org", "1.nodemcu.pool.ntp.org", "2.nodemcu.pool.ntp.org"
    }, function (a,b, c, d ) 
      lastNtpResult = { secs=a, usecs=b, server=c, info=d }
      print(a,b, c, d['offset_us']) printrtc() 
    end, function(e) print (e) end, 1)
end

syslog = (require "syslog")(config.syslog_("192.168.1.68"))

node.egc.setmode(node.egc.ON_ALLOC_FAILURE)

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
   startsync()
   mdns.register(string.format("grandfather-%06x", node.chipid()), { service="http", port=80 })
   local adder = dofile("httpserver.lua")
   dofile("webserver.lua").register(adder)
   adder("GET", "/data", function (c, args, req) 
     require "httpserver-websocket"(c, req)
   end)
   dofile("tftpd.lua")(function (fn)
     if fn == "lfs.img" then
       tmr.create():alarm(1000, tmr.ALARM_SINGLE, function() 
         file.remove("forcelfs.img")
         file.rename("lfs.img", "forcelfs.img")
         node.restart()
       end) 
     end
   end) 
end)

dofile("clockrun.lua")

