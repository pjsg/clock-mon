rate = require 'rate'

a = rate:new({size = 4})

print(a:estimate())
a:push(1.0)
print(a:estimate(), a:last())
a:push(3.0)
print(a:estimate(), a:last())
a:push(4.9)
print(a:estimate(), a:last())
a:push(6.9)
print(a:estimate(), a:last())
a:push(8.9)
print(a:estimate(), a:last())
a:push(10.9)
print(a:estimate(), a:last())
a:push(12.9)
print(a:estimate(), a:last())
