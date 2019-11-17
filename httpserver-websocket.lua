--rewrite from https://github.com/creationix/nodemcu-webide

local function decode(chunk)
  if #chunk < 2 then return end
  local second = string.byte(chunk, 2)
  local len = bit.band(second, 0x7f)
  local offset
  if len == 126 then
    if #chunk < 4 then return end
    len = bit.bor(
      bit.lshift(string.byte(chunk, 3), 8),
      string.byte(chunk, 4))
    offset = 4
  elseif len == 127 then
    if #chunk < 10 then return end
    len = bit.bor(
      -- Ignore lengths longer than 32bit
      bit.lshift(string.byte(chunk, 7), 24),
      bit.lshift(string.byte(chunk, 8), 16),
      bit.lshift(string.byte(chunk, 9), 8),
      string.byte(chunk, 10))
    offset = 10
  else
    offset = 2
  end
  local mask = bit.band(second, 0x80) > 0
  if mask then
    offset = offset + 4
  end
  if #chunk < offset + len then return end

  local first = string.byte(chunk, 1)
  local payload = string.sub(chunk, offset + 1, offset + len)
  assert(#payload == len, "Length mismatch")
  if mask and payload then
    payload = crypto.mask(payload, string.sub(chunk, offset - 3, offset))
  end
  local extra = string.sub(chunk, offset + len + 1)
  local opcode = bit.band(first, 0xf)
  return extra, payload, opcode
end

local function encode(payload, opcode)
  opcode = opcode or 2
  assert(type(opcode) == "number", "opcode must be number")
  assert(type(payload) == "string", "payload must be string")
  local len = #payload
  local head = string.char(
    bit.bor(0x80, opcode),
    bit.bor(len < 126 and len or len < 0x10000 and 126 or 127)
  )
  if len >= 0x10000 then
    head = head .. string.char(
    0,0,0,0, -- 32 bit length is plenty, assume zero for rest
    bit.band(bit.rshift(len, 24), 0xff),
    bit.band(bit.rshift(len, 16), 0xff),
    bit.band(bit.rshift(len, 8), 0xff),
    bit.band(len, 0xff)
  )
  elseif len >= 126 then
    head = head .. string.char(bit.band(bit.rshift(len, 8), 0xff), bit.band(len, 0xff))
  end
  return head .. payload
end

local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
local function acceptKey(key)
  return crypto.toBase64(crypto.hash("sha1", key .. guid))
end

return function (connection, payload)
  register_object('websocket-connection', connection)
  local buffer = false
  local socket = {}
  register_object('websocket-socket', socket)
  local queue = {}
  register_object('websocket-queue', queue)
  local waiting = false
  local function onSend(c)
    while queue[1] do
      local data = queue[1]
      collectgarbage()
      local ok, err = pcall(function() c:send(data, onSend) end)
      if not ok then
        return
      end
      table.remove(queue, 1)
    end
    waiting = false
  end
  function socket.send(...)
    local data = encode(...)
    queue[#queue + 1] = data
    onSend(connection)
  end

  function socket.getPendingCount()
    return #queue
  end

  connection:on("receive", function(c, chunk)
    if buffer then
      buffer = buffer .. chunk
      while true do
        local extra, payload, opcode = decode(buffer)
        if not extra then return end
        buffer = extra
        if opcode == 8 then
          socket.send('', 8)
          if socket.onclose ~= nil then
            print("Closed normally, queue size =", #queue)
            socket.onclose()
            socket.onclose = nil
          end
        elseif opcode == 9 then
          socket.send(payload, 10)
        elseif socket.onmessage then
          socket.onmessage(payload, opcode)
        end
      end
    end
  end)

  connection:on("sent", function(_, _)
  print ("sent", socket.onsent)
    if socket.onsent ~= nil then
      socket.onsent()
    end
  end)

  connection:on("disconnection", function(_, _)
    if socket.onclose ~= nil then
      print("Closed, queue size =", #queue)
      socket.onclose()
    end
    socket = nil
    connection = nil
  end)

  local req = require("httpserver-request")(payload)
  local key = payload:match("Sec%-WebSocket%-Key: ([A-Za-z0-9+/=]+)")
  local filename = "_" .. string.gsub(req.uri.file, "/", "_")
  local ok, serving = pcall(require, filename)
  collectgarbage()
  if req.method == "GET" and key and ok then
    connection:send(
      "HTTP/1.1 101 Switching Protocols\r\n" ..
      "Upgrade: websocket\r\nConnection: Upgrade\r\n" ..
      "Sec-WebSocket-Accept: " .. acceptKey(key) .. "\r\n\r\n",
      function () serving(socket) end)
    buffer = ""
  else
    connection:send(
      "HTTP/1.1 404 Not Found\r\nConnection: Close\r\n\r\n",
      function() connection:close() end)
  end
end
