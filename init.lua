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
    dofile("tftpd.lua")()
  end)
end
