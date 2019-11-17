if file.exists("forcelfs.img") then
  file.remove("lfs.img")
  file.rename("forcelfs.img", "lfs.img")
  rtcmem.write32(0, 0x12345678)
  local result = node.flashreload("lfs.img")
  print("Failed to flashreload", result)
end

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

if rtcmem.read32(0) == 0x12345678 then
  rtcmem.write32(0, 0)

  local _init = node.flashindex('_init')

  if not _init then
    node.flashreload("lfs.img")
    print("Failed to load the lfs image")
  else
    _init()

    wifi.setmode(wifi.STATION)
    dofile("clockinit.lua")
    pcall(function ()
      dofile("tftpd.lua")(newlfsimage)
    end)

    --enduser_setup.start(function() 
    --  tmr.create():alarm(200, tmr.ALARM_SINGLE, function () 
    --    enduser_setup.stop()
    --    dofile("clockinit.lua")
    --  end)
    --end)
  end
else
  -- fast reboot. probably not working
  print("Fast reboot, probably not working....")
  pcall(function ()
    wifi.setmode(wifi.STATION)
    dofile("tftpd.lua")(newlfsimage)
  end)
end
