local M = {}

local m = require 'mqtt_w'
local stats = require 'stats'

local Rate = {}

function Rate:push(v)
  if #self.prev > 0 and self.post then
    local msg = {}
    msg[self.post] = (v - self.prev[#self.prev]) / self.div
    msg[self.post .. "_ppm"] = (1 - msg[self.post]) * 1000000
    m.send("processed/data", msg)
  end
  table.insert(self.prev, v)
  if #self.prev > self.size then
    table.remove(self.prev, 1)
  end
  self.index = self.index + 1
  if self.index >= self.every then
    self.index = 0
    if self.overflow then
      self.overflow:push(v)
    end
  end
end

function Rate:getHistory(div)
  local result = {}

  div = div or 1
  div = div * 2

  for i = 1, #self.prev - 1 do
    table.insert(result, (self.prev[i + 1] - self.prev[i]) / div)
  end
  return result
end

function Rate:estimate() 
  local ok, res = pcall(function() 
  local last = #self.prev
  local first = last - self.every - 1
  if first < 1 then
    first = 1
  end
  if self.div > 0 then
    local duration = self.prev[last] - self.prev[first]
    local step = self.prev[2] - self.prev[1]
    -- this should be roughly a multiple of div
    step = math.floor((step + self.div / 2) / self.div) * self.div
    return duration / (step * (last - first))
  else
    local mean = stats.mean(self.prev)
    return mean
  end
  end)
  if ok then
    return res
  else
    return nil
  end
end

function Rate:last() 
  local ok, res = pcall(function() 
  local step = self.prev[#self.prev] - self.prev[#self.prev - 1]
  local duration = step
  -- this should be roughly a multiple of 2
  step = math.floor((step + 1) / 2) * 2
  return duration / step 
  end)
  if ok then
    return res
  else
    return nil
  end
end

function Rate:now()
  local ok, res = pcall(function() return self.prev[#self.prev] end)
  if ok then
    return res
  else
    return nil
  end
end

Rate.__index = Rate

function M:new(o) 
  o = o or {}
  if not o.every then
    o.every = o.size - 1
  end
  o.index = 0
  setmetatable(o, Rate)
  o.prev = {}
  return o
end

return M
