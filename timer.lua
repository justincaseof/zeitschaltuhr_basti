-- this is a comment
print("Timer")

--------------------------------------------
-- GPIO Setup
--------------------------------------------
print("Setting Up GPIO...")

-- Note: Pin index starts at 0 (for D0 or equivalent pin function)
setupwifi_pin           = 1     --> = D1 --> the "FLASH" button on NodeMCU dev kit board
                                    -- NOTE: should already have been defined in 'init.lua'
button_and_red_led_pin  = 0     --> = D0 
                                    -- = the "USER" button on NodeMCU dev kit board. ... NOTE: should already have been used as input in 'init.lua' 
                                    -- = the red LED on NodeMCU dev kit board. ... NOTE: should already have been defined in 'init.lua' 
blue_led_pin            = 4     --> = D4
relais_out_pin          = 2     --> = D2
gpio.mode(button_and_red_led_pin,   gpio.OUTPUT)
gpio.mode(blue_led_pin,             gpio.OUTPUT)
gpio.mode(relais_out_pin,           gpio.OUTPUT)

function switchOn()
    gpio.write(button_and_red_led_pin,  gpio.LOW)
    gpio.write(relais_out_pin,          gpio.HIGH)
end

function switchOff()
    gpio.write(button_and_red_led_pin,  gpio.HIGH)
    gpio.write(relais_out_pin,          gpio.LOW)
end

function isOn()
    return (gpio.read(relais_out_pin) == 0)
end

local FIRST_RUN = true

-- initially (and permanently) switch on blue LED on ESP8266 board
gpio.write(blue_led_pin, gpio.LOW)
-- initially switch off the relais
switchOff()

-----------------------------
-- WIFI setup switch check --
-----------------------------
-- check for active wifi setup during cycle
-- var 'local setup_wifi = gpio.read(setupwifi_pin)' has been previously defined by init.lua script
function isWifiSetupActive()
    if setupwifi_pin then
        return gpio.read(setupwifi_pin)==0
    end
    return false
end

----------------------------------
-- Timer/Scheduler config stuff --
----------------------------------
-- Line format: {identifier}:{from}:{to}
if file.open("timerconfigs.txt", "rw") then
    print(" FILE!")
    myline = "0:1:2"
    myline = file.readline()
    while ( myline ~= nil and myline ~= "" ) do
        print(" --> " .. myline)
        myline = file.readline()
    end
    file.close()
end
-- DEBUG: set up dummy config
TIMERDEFINITIONS = { }
TIMERDEFINITIONS['tim0'] = { 
    ["from"]            = 360, 
    ["to"]              = 480, 
}
TIMERDEFINITIONS['tim1'] = { 
    ["from"]            = 1100, 
    ["to"]              = 1260, 
}

local function addOrUpdateTimer(_timerId, _from, _to)
    print("adding Timer -->")
    print("  _timerId: " .. _timerId)
    print("  val.from: " .. _from)
    print("  val.to  : " .. _to)

    -- clear old values
    for k,v in pairs(TIMERDEFINITIONS) do
        TIMERDEFINITIONS[k] = nil
    end

    TIMERDEFINITIONS[_timerId] = {
        ["from"]            = _from, 
        ["to"]              = _to
    }
end

----------
-- SNTP --
----------
sntpTimeSyncRunning = false
sntpTimeSyncDone    = false
function syncSNTP()
    sntpServers = {
        "0.pool.ntp.org",
        "1.pool.ntp.org",
        "2.pool.ntp.org",
        "3.pool.ntp.org",
        "ptbtime1.ptb.de",
        "ptbtime2.ptb.de",
        "ptbtime3.ptb.de",
    }
    if ( not sntpTimeSyncRunning and not sntpTimeSyncDone ) then
        sntpTimeSyncRunning = true
        sntp.sync(
            sntpServers, 
            function(sec, usec, server, info)
                print('SNTP sync done: ', sec, usec, server)
                sntpTimeSyncRunning = false
                sntpTimeSyncDone = true
            end,
            function()
                print('SNTP sync failed!')
                sntpTimeSyncRunning = false
                sntpTimeSyncDone = false
            end
        )
    end
end

----------
-- mDNS --
----------
local function enable_mDNS_registration() 
    mdns.register("nodemcutimer", { description="HeizungsTimer-BaNe", service="http", port=80, location="DWNTS10" })
    end
local function disable_mDNS_registration() 
    mdns.close()
end

------------------
-- STATES  --
------------------
-- 0: off, 1: on, 2: timer active
relais_state = 2
-- initial delay (FIXME TODO: persist in flash)
seconds_until_switchoff_counter = 1800

----------------
-- Timers     --
----------------

-- DO NOT CHANGE THIS TIMER DEFINITION!
local timer1_id = 0
local timer1_timeout_millis = 1000
tmr.register(timer1_id, timer1_timeout_millis, tmr.ALARM_SEMI, function()
    -- SNTP TIME --
    tm = rtctime.epoch2cal(rtctime.get())
    unix_time_millis = string.format("%04d/%02d/%02d %02d:%02d:%02d", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"])
    minutesofday = tm["hour"] * 60 + tm["min"]
    syncSNTP()  -- ask for sync

    -- LOG --
    print("tick")
    --print("  -> relais_state: " .. (relais_state or "?"))
    print("  -> IP: " .. (wifi.sta.getip() or "?"))
    print("  -> time: " .. unix_time_millis)
    print("  -> minutesofday: " .. minutesofday)
    
    -- 1) identify and calculate railais_state --
    local _switchOnRequested    = false
    local _switchOffRequested   = false
    local _in_range             = false
    for k, v in pairs(TIMERDEFINITIONS) do
        local previous_state        = relais_state
        local _from                 = v["from"]
        local _to                   = v["to"]
        _in_range = (_in_range) or (minutesofday >= _from and minutesofday <= _to)
        print("  -> Processing timer '" .. k .. "': from=" .. _from .. ", to=" .. _to)
        print("  -> _in_range: " .. ((_in_range and "true") or "false"))
    end

    -- 3.1) switch in first run
    if (_in_range) then
        print("  ---- ON -----")
        switchOn()
    else
        print("  ---- OFF -----")
        switchOff()
    end

    -- === WIFI SETUP CHECK ===
    -- check for active wifi setup during cycle
    -- var 'local setup_wifi = gpio.read(setupwifi_pin)' has been previously defined by init.lua script
    if isWifiSetupActive() then
        print("SETUP_WIFI_RESTART")
        node.restart()
    end
    -- === /WIFICHECK ===

	-- GC (doesn't help from out of memory, though)
    collectgarbage()
    print("  -> heap: " .. node.heap())
    -- /GC

    tmr.start(timer1_id)    -- restart timer for creating a proper loop
end)
tmr.start(timer1_id)
print(" timer1 started (switch relais)");

----------------
-- Init Wifi  --
----------------
-- read config from FS
client_ssid = "notinitialized"
client_password = "notinitialized"
if file.open("client_ssid.txt", "r") then
    client_ssid = file.readline()
    file.close()
end
collectgarbage()
if file.open("client_password.txt", "r") then
    client_password = file.readline()
    file.close()
end
collectgarbage()
print("client_ssid: '" .. client_ssid .. "'")
print("client_password: '" .. client_password .. "'")
-- a fix for URL-encoded character ',' (comma)
print("  after URL-char-decode: " .. string.gsub(client_password, "%%2C", ","))

-- setup station mode
wifi.setmode(wifi.STATION)
-- less energy consumption
wifi.setphymode(wifi.PHYMODE_G)
-- edit config
local wifi_client_config = {}
wifi_client_config["ssid"] = client_ssid
wifi_client_config["pwd"] = client_password
wifi.sta.config(wifi_client_config) 
wifi.sta.connect()
print(" connecting to: " .. client_ssid)

--[[ 
-- === WIFI LISTENERS ===
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function(T)
        print("\n\tSTA - GOT IP".."\n\tStation IP: "..T.IP.."\n\tSubnet mask: "..T.netmask.."\n\tGateway IP: "..T.gateway)
        enable_mDNS_registration()
    end
)
wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, function(T)
        print("\n\tSTA - DISCONNECTED".."\n\tSSID: "..T.SSID.."\n\tBSSID: "..T.BSSID.."\n\treason: "..T.reason)
        disable_mDNS_registration()
    end
)
wifi.eventmon.register(wifi.eventmon.STA_AUTHMODE_CHANGE, function(T)
        print("\n\tSTA - AUTHMODE CHANGE".."\n\told_auth_mode: "..T.old_auth_mode.."\n\tnew_auth_mode: "..T.new_auth_mode)
        disable_mDNS_registration()
    end
)
-- === /WIFI LISTENERS ===
]] --

----------------
-- Web Server --
----------------
print("Starting Web Server...")
-- a simple HTTP server
if srv~=nil then
  print("found an open server. closing it...")
  srv:close()
  print("done. now tyring to start...")
end

local function Sendfile(sck, filename, sentCallback)
    print("opening file '" .. filename .. "'...")
    if not file.open(filename, "r") then
        print(" cannot open file '" .. filename .. "'")
        sck:close()
        SEMAPHORE_TAKEN = false
        print("RESET SEMAPHORE_TAKEN")
        return
    end
    local function sendChunk()
        local line = file.read(512)
        if (line and #line>0) then 
            sck:send(line, sendChunk) 
        else
            file.close()
            collectgarbage()
            if sentCallback then
                sentCallback()
                SEMAPHORE_TAKEN = false
                print("RESET SEMAPHORE_TAKEN")
            else
                sck:close()
            end
        end
    end
    sendChunk()
end

-- application/javascript -- text/css -- text/html --
local function getContentType(path)
   if (string.match(path, "\.(html)$")) then
        result = "text/html"
    elseif (string.match(path, "\.(css)$")) then
        result = "text/css"
    elseif (string.match(path, "\.(js)$")) then
        result = "application/javascript"
    else
        result = "text"
    end
    print("  ### Content-Type = " .. result)
    return result
end

----------------
-- Web Server --
----------------
--[[
"REST":
============
    GET     TODO
    POST    http://ip:port/timer/{timer_id} --> create/update timer
    DELETE  http://ip:port/timer/{timer_id} --> delete timer
]]--
SEMAPHORE_TAKEN = false
-- == START ACTUAL WEB SERVER ==
local srv = net.createServer(net.TCP)
srv:listen(80, function(conn)
    conn:on("receive", function(sck, request_payload)
        if (SEMAPHORE_TAKEN) then
            sck:close()
            return
        end

        SEMAPHORE_TAKEN = true


        -- == DATA == --
        local payload = ""
        if request_payload == nil or request_payload == "" then
            payload = ""
        else
            payload = request_payload
        end

        --print(payload)        -- DEBUG

        -- === FUNCTIONS ===
        local function respondRoot(sck, path)
            if (path == nil or path == "" or path == "/" or path == "index.html") then
                path = "slider.html"
            end
            if ( string.sub(path, 1, 1) == "/" ) then                     -- "startsWith"
                path = string.sub(path, 2)
            else
                
            end
            print("  # path: '" .. path .. "'")
            local contentType = getContentType(path)
            sck:send("HTTP/1.1 200 OK\r\n" ..
                "Server: NodeMCU on ESP8266\r\n" ..
                "Connection: close\r\n" .. 
                "Content-Type: " .. contentType .. "; charset=UTF-8\r\n\r\n", 
                function()
                    Sendfile(sck, path, 
                        function() 
                            --sck:send("seconds_until_switchoff_counter: " .. seconds_until_switchoff_counter or "?", 
                            --function() 
                                sck:close()
                                sck = nil
                                collectgarbage()
                            --end)
                        end)
                end)
        end

        local function respondTimers()
            local first = true
            local json = "{"
            for _timerId, val in pairs(TIMERDEFINITIONS) do
                if (first) then
                    first = false
                else
                    json = json .. ","
                end
                json = json .. "\"" .. _timerId .. "\":" .. "{" ..
                        "\"from\":" .. val["from"] .. "," ..
                        "\"to\":" .. val.to ..
                    "}"
            end
            json = json .. "}"
            sck:send("HTTP/1.1 200 OK\r\n" ..
                "Server: NodeMCU on ESP8266\r\n"..
                "Access-Control-Allow-Origin: *\r\n" ..
                "Connection: close\r\n" .. 
                "Content-Type: application/json; charset=UTF-8\r\n\r\n" ..
                json,
                function()
                    SEMAPHORE_TAKEN = false
                    sck:close()
                    sck = nil
                    collectgarbage()
                end)
        end

        local function respondOK()
            sck:send("HTTP/1.1 200 OK\r\n" ..
                "Server: NodeMCU on ESP8266\r\n", 
                function()
                    sck:close()
                    sck = nil
                    collectgarbage()
                end)
        end

        local function respondError()
            sck:send("HTTP/1.1 400 Bad Request\r\n" ..
                "Server: NodeMCU on ESP8266\r\n", 
                function()
                    sck:close()
                    sck = nil
                    collectgarbage()
                end)
        end

        local function handleGET(payload, path)
            --print("### handleGET() ###")
            -- path?
            if string.match(path, "status") then
                --print(" - respondStatus()")
                respondStatus(sck)
            elseif string.match(path, "timer") then
                respondTimers()
            else
                --print(" - respondMain()") 
                respondRoot(sck, path)
            end
        end

        local function safelyUpdateTimersFromJSON(_json)
            print(" ---1 ")
            local result = sjson.decode(_json)
            print(" ---2 ")
            for _timerId, val in pairs(result) do 
                print(" --->>> ")
                addOrUpdateTimer(_timerId, val["from"], val["to"])
            end
        end

        local function handlePOST(payload, path)
            print("### handlePOST() ###")
            
            if string.match(path, "timers") then
                -- POST @ path "/timers" --> application/json
                local _json = string.match(payload, "{.*}")      -- extract JSON from payload
                print("TIMEEEEEERRRRRRRRRRRRRRRRRRRRRRRRSSSSSSSSSSSSSSSSSSSSSSSSSS")
                print("------------")
                print(_json)
                print("------------")
                safelyUpdateTimersFromJSON(_json)
            end

            respondTimers()

        end
        -- === FUNCTIONS - END ===
    
        -- === ACTUAL EVALUATION ===
        local GET_requestpath = string.match(payload, "GET (.*) HTTP") --or "N/A"
        local POST_requestpath = string.match(payload, "POST (.*) HTTP") --or "N/A"
        print(" GET_requestpath: " .. (GET_requestpath or "???") )
        print(" POST_requestpath: " .. (POST_requestpath or "???") )
        
        if GET_requestpath then
            handleGET(payload, GET_requestpath)
        elseif POST_requestpath then
            handlePOST(payload, POST_requestpath)
        else
            --print("# cannot handle request. olny GET and POST are allowed.")
            respondError()
        end

        -- === GC: GARGABE COLLECTION (i have some kind of mem leak) ===
        request_payload = nil
        payload = nil
        GET_requestpath = nil
        POST_requestpath = nil
        collectgarbage()
        -- === /GC ===

    end)
        
end)
