-- config.lua
--
local configs = {}

return function (name)
  if configs[name] then
    return configs[name]
  end

  local filename = name .. ".json"

  local config = {}
  local cache = {}

  local mt = {
    __index = function(t, k) 
      if k == "json" then
        return sjson.encode(cache)
      end
      if k == "table" then
        return cache
      end
      if k:sub(-1) == '_' then
        return function(def) 
          local key = k:sub(1, -2)
          if cache[key] == nil then
            cache[key] = def
          end
          return cache[key]
        end
      end
      return (cache[k])
    end,
    __newindex = function(t, k, v)
      cache[k] = v
      file.open(filename, "w+")
      file.write(sjson.encode(cache))
      file.close()
      return 1
    end
  }

  setmetatable(config, mt)

  if file.open(filename) then
    cache = sjson.decode(file.read())
    file.close()
  elseif name == 'config' then
    cache = { tz="eastern" }
  else
    cache = {}
  end

  configs[name] = config

  return config
end
