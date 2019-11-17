-- httpserver

local H = {}

local function sendDocument(conn, fn)
  if fn == nil then
    conn:send("HTTP/1.0 404 Not found\r\n\r\n")
    conn:on('sent', function (c)
      c:close()
    end)
    return
  end

  conn:on('sent', function(c)
     local buf = fn()
     if buf then
       c:send(buf)
     else
       c:close()
     end
  end)

  local buf = fn()
  conn:send(buf)
end

-- returns a function that reads blocks of the file and then nil
local function fileReader(fn)
  local f = file.open(fn)

  if f == nil then
    return nil
  end

  return function() 
    local buf = f:read(1024)
    if not buf then
      f:close()
    end
    return buf
  end
end

local function getReader(fn)
  local result = fileReader(fn)
  if result then
    return result
  end

  local ok, result = pcall(require, "__" .. string.gsub(fn, "[.]", "_"))
  if ok then
    return result()
  end
end

function sendfile(conn, fn)
  sendDocument(conn, getReader(fn))
end

H["GET/"] = function(conn)
  sendfile(conn, "index.html")
end

local srv = net.createServer(net.TCP)
local function onNewConnection(conn)
    conn:on("receive", function(c, request)
        collectgarbage()
        local _, _, method, path, vars = string.find(request, "([A-Z]+) (.*)?(.+) HTTP")
        if method == nil then
            _, _, method, path = string.find(request, "([A-Z]+) (.*) HTTP")
        end
        local _GET = {}
        if (vars ~= nil)then
            for k, v in string.gmatch(vars, "(%w+)=(%w+)&*") do
                _GET[k] = v
            end
        end

        collectgarbage()
        local f = (H[method .. path])
        if f == nil then
           sendfile(c, "notfound.html")
        else
           f(c, _GET, request)
        end        
    end)
end

tmr.create():alarm(1000, tmr.ALARM_SEMI, function(t)
  local ok = pcall(function() srv:listen(80, onNewConnection) end)
  if not ok then
    t:start()
  end
end)

return function (method, path, fn) 
  H[method .. path] = fn
end
