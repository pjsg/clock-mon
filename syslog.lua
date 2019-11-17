-- syslog.lua

return function(host)
   local conn = net.createUDPSocket()
   local syslog = {}
   function syslog:send(string) 
      print(string)
      conn:send(514, host, "<142>" .. string)
   end
   return syslog
end
 
