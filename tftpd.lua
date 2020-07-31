return function(close_cb)
    local port = 69 --default

    local _tblk=0 --block counter
    local _lock=nil --lock for operations
    local _fn={} --filename store between packets
    local _conn = nil -- connection store

    local _tmrid = tmr.create()
    local _retry_max = 5
    local _retry = 5
    local _tmrtimeout = 3000

    local function reset()
        _tblk=0
        _lock = nil
        _fn = {}
        _tmrid:stop()
        _conn = nil
        _retry = _retry_max
        uart.write(0, 'R')
        collectgarbage()  --gc when finished
    end

    local function sendack(port, ip, c,n)
        local msb = math.floor(n/256) --assumes int firmware
        local lsb = n - msb*256
        collectgarbage()
        c:send(port, ip, "\0\4"..string.char(msb, lsb))
    end

    local function sendblk(port, ip, c)
        local msb = math.floor(_tblk/256) --assumes int firmware
        local lsb = _tblk - msb*256
        local b=string.char(msb, lsb)

        collectgarbage()
        if(file.open(_fn,"r")==nil) then
            c:send(port, ip, "\0\5\0\1\0") --Error: 1=file not found
            reset()
            return
        end
        local r = ""
        if(file.seek("set", (_tblk-1)*512)~=nil) then
            r = file.read(512)
        end
        file.close()
        if(r == nil) then
            r = ""
        end
        c:send(port, ip, "\0\3"..b..r)
        if(r:len() ~= 512) then
            _lock=4 -- done, wait for ack
        end
    end
    
    local function timeoutCB(port, ip)
        _tmrid:stop()
        _retry=_retry-1
        if(_retry~=0) then
            uart.write(0,"*")
            if(_lock==2) then
                sendack(port, ip, _conn, _tblk-1) --retransmit last ACK
            else -- _lock is 1 or 4
                sendblk(port, ip, _conn)  --retransmit data
            end
            _tmrid:alarm(_tmrtimeout * (_retry_max - _retry), 0, function () timeoutCB(port, ip) end)
            return
        end
        print("Connection timed out")
        if(_lock == 2) then
            file.remove(_fn) --remove incomplete file
        end
        reset()
    end

    local function alarmstop()
        _tmrid:stop()
    end
    local function alarmstart(port, ip)
        _tmrid:alarm(_tmrtimeout, 0, function() timeoutCB(port, ip) end)
    end

    local s=net.createUDPSocket()
    s:on("receive", function(c,r, port, ip) 
        local op=r:byte(2)

        if(op==1 or op==2) then
            if(_lock) then
                return
            end
            _conn=c
            _fn=string.match(r,"..(%Z+)")
            _lock=op
            _tblk=1
        elseif(op==3 or op==4) then
            local b=r:byte(3)*256+r:byte(4)
            if(b~=_tblk) then
                return
            end
            alarmstop()
            _retry= _retry_max
        end

        if(op==1) then
            --RRQ
            uart.write(0,"TFTP RRQ '".._fn.."': ")
            if(file.open(_fn, "r")==nil) then
                c:send("\0\5\0\1\0") --Error: 1=file not found
                reset()
                return
            end
            file.close()
            sendblk(port, ip, c)
        elseif(op==2) then
            --WRQ
            uart.write(0,"TFTP WRQ '".._fn.."': ")
            -- overwrite file...
            if(file.open(_fn,"w")==nil) then
                c:send("\0\5\0\2\0") --Error: 2=access violation
                reset()
                return
            end
            file.close()
            sendack(port, ip, c,0)
        elseif(op==3) then
            --DATA received for a WRQ
            if(_lock~=2) then
                return
            end
            local sz=r:len()-4
            if(file.open(_fn,"a")==nil) then
                c:send(port, ip, "\0\5\0\1\0") --Error: 1=file not found
                reset()
                return
            end
            if(file.write(r:sub(5))==nil) then
                c:send(port, ip, "\0\5\0\3\0") --Error: 3=no space left
                reset()
                return
            end
            sendack(port, ip, c,_tblk)
            uart.write(0,"#")
            file.close()
            _tblk=_tblk+1
            if(sz~=512) then
                print(" done!")
                local thefn = _fn
                reset()
                if close_cb then
                  close_cb(thefn)
                end
            end
        elseif(op==4) then
            --ACK received for a RRQ
            if(_lock~=1 and _lock~=4) then
                return
            end
            uart.write(0,"#")
            _tblk=_tblk+1
            if(_lock==1) then
                sendblk(port, ip, c)
            else
                print(" done!")
                reset()
            end
        else
            --ERROR: 4=illegal op
            collectgarbage()
            c:send(port, ip, "\0\5\0\4\0")
            return
        end
        if (_lock) then 
            alarmstart(port, ip)
        end
    end)
    function startit()
      s:listen(port)
      print("TFTP server running on port "..tostring(port))
    end

    tmr.create():alarm(1000, tmr.ALARM_AUTO, function (t) 
      if wifi.sta.getip() ~= nil then
        pcall(startit)
	t:stop()
      end
    end)
    return s
end
