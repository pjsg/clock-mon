-- webserver.lua

local M = {}

local config = require "config"("config")

local function wrapit(fn)
  return function (conn)
    local buf = "HTTP/1.1 200 OK\r\n" ..
                "Content-type: application/json\r\n" ..
                "Connection: close\r\n\r\n" ..
                sjson.encode(fn())
    local now = tmr.now()
    conn:send(buf, function(c) print ('closing socket after', tmr.now() - now) c:close() end)
  end
end

local function getStatus()
  local R = {}

  R.time = {rtctime.get()}
  R.config = config.table
  R.ntp = lastNtpResult
  R.freemem = node.heap()
  R.mac = wifi.sta.getmac()
  -- R.sw_build, _ = node.LFS.index()
  local _,_,info = node.info("sw_version")
  if info then
    R.hw_build = info
  end
  return R 
end

M.getStatus = getStatus

function M.register(adder)
  local function addjson(path, fn)
    adder("GET", path, wrapit(fn)) 
  end
  addjson("/status", getStatus)
  
  adder("POST", "/set", function (conn, vars)
    wrapit(getStatus)(conn)
  end)
end

return M
