function dumpit()
  local hasher = crypto.new_hash('sha1')
  local offset = 0x3fb000
  for addr = 0, 0x4fff, 128 do
    hasher:update(node.peek(addr + offset, 128))
  end
  local hash = string.sub(encoder.toHex(hasher:finalize()), 1, 16)

  local current = file.getcontents("hashcount")
  local num = 1
  if current then
    num = sjson.decode(current).num
  end
  local d = file.open(string.format("flash-%d-%s", num, hash), "w")
  for addr = 0, 0x4fff, 128 do
    d:write(node.peek(addr + offset, 128))
  end
  d:close()
  file.putcontents("hashcount", sjson.encode({num=num + 1}))
  
end
