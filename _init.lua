if file.exists("forcelfs.img") then
  file.remove("lfs.img")
  file.rename("forcelfs.img", "lfs.img")
  file.remove("index.html")
  rtcmem.write32(0, 0x12345678)
  local result = node.LFS.reload("lfs.img")
  print("Failed to LFS.reload", result)
end

package.loaders[3] = function(module) return node.LFS.get(module) end

intensity = 1
local colors = {off=string.char(0,0,0), red=string.char(0, 255, 0), green=string.char(255,0,0), blue=string.char(0,0,255)}
local buffer = ws2812.newBuffer(3, 3)
buffer:fill(0, 0, 0)
function setled(led, color)
  buffer:set(led, colors[color])
  local temp = ws2812.newBuffer(3, 3)
  temp:mix(intensity * 255, buffer)
  ws2812.init()
  ws2812.write(temp)
  -- Now shut off the blue LED
  tmr.create():alarm(100, tmr.ALARM_SINGLE, function ()
    gpio.mode(4, gpio.OUTPUT)
    gpio.write(4, 1)
  end)
end
setled(1, 'red')

gpio.mode(8, gpio.OUTPUT)
gpio.write(8, 1)

i2c.setup(0, 3, 5, i2c.FAST)


tmr.create():alarm(300 * 1000, tmr.ALARM_SINGLE, function() 
  rtcmem.write32(0, 0x12345678)
end)

function newlfsimage(fn)
  if fn == "lfs.img" then
    tmr.create():alarm(1000, tmr.ALARM_SINGLE, function() 
      file.remove("forcelfs.img")
      file.rename("lfs.img", "forcelfs.img")
      node.restart()
    end) 
  end
end

function startapp()
    setled(1, 'off')
    wifi.setmode(wifi.STATION)
    require("clockinit")
    pcall(function ()
      require("tftpd")(newlfsimage)
    end)

    --enduser_setup.start(function() 
    --  tmr.create():alarm(200, tmr.ALARM_SINGLE, function () 
    --    enduser_setup.stop()
    --    dofile("clockinit.lua")
    --  end)
    --end)
end

tmr.create():alarm(1000, tmr.ALARM_SINGLE, function() 
  if rtcmem.read32(0) == 0x12345678 then
    rtcmem.write32(0, 0)

    startapp()
  else
    -- fast reboot. probably not working
    print("Fast reboot, probably not working....")
    pcall(function ()
      setled(1, 'green')
      wifi.setmode(wifi.STATION)
      require("tftpd")(newlfsimage)
    end)
    -- But try starting it in five minutes. Plenty of time to get in
    tmr.create():alarm(1000 * 300, tmr.ALARM_SINGLE, startapp)
  end
end)

require 'dumpit'

tmr.create():alarm(1000 * 180, tmr.ALARM_SINGLE, function () if wifi.sta.getip() == nil then dumpit() end end)
