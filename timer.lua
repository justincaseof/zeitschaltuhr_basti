-- Note: Pin index starts at 0 (for D0 or equivalent pin function)
setupwifi_pin           = 1     --> = D1 --> the "FLASH" button on NodeMCU dev kit board
                                    -- NOTE: should already have been defined in 'init.lua'
button_and_red_led_pin  = 0     --> = D0 
                                    -- = the "USER" button on NodeMCU dev kit board. ... NOTE: should already have been used as input in 'init.lua' 
                                    -- = the red LED on NodeMCU dev kit board. ... NOTE: should already have been defined in 'init.lua' 
relais_out_pin          = 2     --> = D2
CONTINUOUS_MODE_IN_PIN  = 3     --> = D3
gpio.mode(button_and_red_led_pin,   gpio.OUTPUT)
gpio.mode(relais_out_pin,           gpio.OUTPUT)
gpio.mode(CONTINUOUS_MODE_IN_PIN,   gpio.INPUT, gpio.PULLUP)

--------------------------------------------
-- HELPER
--------------------------------------------
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

function isContinuousModeActive()
    if CONTINUOUS_MODE_IN_PIN then
        return gpio.read(CONTINUOUS_MODE_IN_PIN) == 0
    end
    return false
end

function isStringEmpty(s)
  return s == nil or s == ''
end

function isWifiSetupActive()
    if setupwifi_pin then
        return gpio.read(setupwifi_pin) == 0
    end
    return false
end

-- initially switch off the relais
switchOff()

----------------------------------
-- Timer/Scheduler config stuff --
----------------------------------
TIMERDEFINITIONS = { }

local function addOrUpdateTimer(_timerId, _from, _to)
    print("adding Timer -->")
    print("  _timerId: " .. _timerId)
    print("  val.from: " .. _from)
    print("  val.to  : " .. _to)

    TIMERDEFINITIONS[_timerId] = {
        ["from"]            = tonumber(_from), 
        ["to"]              = tonumber(_to)
    }
end

---### file handling ###
TIMER_CONFIG_FILE_NAME = "timerconfigs.txt"
-- Line format: {identifier}:{from}:{to}
local fd = file.open(TIMER_CONFIG_FILE_NAME, "r")
if fd ~= nil then
    local myline = fd:readline()
    while ( myline ~= nil and myline ~= "" ) do
    --    print(" --> timer config line: \r\n" .. myline)
        _line_id, _line_from, _line_to = string.match(myline, "^(.+):(.+):(.+)$")
        if (not isStringEmpty(_line_id)) and (not isStringEmpty(_line_from)) and (not isStringEmpty(_line_to)) then 
            addOrUpdateTimer(_line_id, _line_from, _line_to)
        else
            print("  --> Illegal line!")
        end
        myline = fd:readline()
    end
    fd:close()
    fd = nil
else
    print(" :-( no timer config file found (" .. TIMER_CONFIG_FILE_NAME ..")")
end
collectgarbage()

local function writeTimerConfigToFile()
    -- UPDATE FILE
    collectgarbage()
    fd = file.open(TIMER_CONFIG_FILE_NAME, "w+")
    for k, v in pairs(TIMERDEFINITIONS) do
        local _from = v["from"]
        local _to   = v["to"]
        fd:write( k .. ':' .. _from .. ':' .. _to .. '\r\n' )
        fd:flush()
    end
    fd:close()
    fd = nil
    collectgarbage()
end

----------
-- SNTP --
----------
sntpTimeSyncRunning = false
sntpTimeSyncDone    = false
function syncSNTP()
    sntpServers = {
        "1.pool.ntp.org",
        "3.pool.ntp.org",
        "ptbtime1.ptb.de",
        "ptbtime3.ptb.de",
    }
    if ( not sntpTimeSyncRunning and not sntpTimeSyncDone ) then
        sntpTimeSyncRunning = true
        LED_blue_STATE = 4
        sntp.sync(
            sntpServers, 
            function(sec, usec, server, info)
                print('SNTP sync done: ', sec, usec, server)
                sntpTimeSyncRunning = false
                sntpTimeSyncDone = true
                LED_blue_STATE = 1  -- ON
            end,
            function()
                print('SNTP sync failed!')
                sntpTimeSyncRunning = false
                sntpTimeSyncDone = false
                LED_blue_STATE = 3  -- FAST_FLASH
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
-- 0=OFF, 1=ON, 2=SLOW FLASH, 3=FAST FLASH, 4=SUPER FAST FLASH
LED_blue_STATE = 2      -- see "init.lua". HAS TO BE USED BY LED STATE TIMER THERE!

----------------
-- Timers     --
----------------

-- DO NOT CHANGE THIS TIMER DEFINITION!
local timer1_id = 0
local timer1_timeout_millis = 1000
tmr.register(timer1_id, timer1_timeout_millis, tmr.ALARM_SEMI, function()
    -- SNTP TIME --
    tm = rtctime.epoch2cal(rtctime.get())
    timeAsString = string.format("%04d/%02d/%02d %02d:%02d:%02d", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"])
    minutesofday = tm["hour"] * 60 + tm["min"]
    syncSNTP()  -- ask for sync

    -- LOG --
    print("tick")
    --print("  -> relais_state: " .. (relais_state or "?"))
    print("  -> IP: " .. (wifi.sta.getip() or "?"))
    print("  -> time: " .. timeAsString)
    print("  -> minutesofday: " .. minutesofday)

    local _switch_on = false
    if isContinuousModeActive() then
        -- ######### CONTINUOUS MODE #########
        print("  -> We're in CONTINUOUS mode. Relais is on.")
        _switch_on = true
    else
        -- ######### TIMER MODE #########
        -- 1) identify and calculate railais_state --
        
        for k, v in pairs(TIMERDEFINITIONS) do
            local previous_state        = relais_state
            local _from                 = v["from"]
            local _to                   = v["to"]
            _switch_on = (_switch_on) or (minutesofday >= _from and minutesofday <= _to)
            print("  -> Processing timer '" .. k .. "': from=" .. _from .. ", to=" .. _to)
            print("  -> _switch_on: " .. ((_switch_on and "true") or "false"))
        end
    end

    -- 3.1) switch in first run
    if (_switch_on) then
        print("  ---- ON -----")
        switchOn()
    else
        print("  ---- OFF -----")
        switchOff()
    end

    -- === WIFI SETUP CHECK ===
    if isWifiSetupActive() then
        print("SETUP_WIFI_RESTART")
        node.restart()
    end
    -- === /WIFICHECK ===

	-- GC (doesn't help from out of memory, though)
    collectgarbage()
    --print("  -> heap: " .. node.heap())
    -- /GC

    tmr.start(timer1_id)    -- restart timer for creating a proper loop
end)
tmr.start(timer1_id)

----------------
-- Init Wifi  --
----------------
-- read config from FS
local client_ssid = "notinitialized"
local client_password = "notinitialized"
local fd = file.open("client_ssid.txt", "r")
if fd ~= nil then
    client_ssid = fd:readline()
    fd:close()
    fd = nil
end
collectgarbage()
local fd = file.open("client_password.txt", "r")
if fd ~= nil then
    client_password = fd:readline()
    fd:close()
    fd = nil
end
collectgarbage()
print("client_ssid: '" .. client_ssid .. "'")
print("client_password: '" .. client_password .. "'")

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

client_ssid = nil
client_password = nil
collectgarbage()

----------------
-- Web Server --
----------------
print("Starting Web Server...")
if srv~=nil then
  print("found an open server. closing it...")
  srv:close()
  print("done. now tyring to start...")
end

local function Sendfile(sck, filename, sentCallback)
    if not file.open(filename, "r") then
        print(" cannot open file '" .. filename .. "'")
        sck:close()
        SEMAPHORE_TAKEN = false
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
    return result
end

----------------
-- Web Server --
----------------
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
                                sck:close()
                                sck = nil
                                collectgarbage()
                        end)
                end)
        end

        local function sendJSON(_json)
            sck:send("HTTP/1.1 200 OK\r\n" ..
                    "Server: NodeMCU on ESP8266\r\n"..
                    "Access-Control-Allow-Origin: *\r\n" ..
                    "Connection: close\r\n" .. 
                    "Content-Type: application/json; charset=UTF-8\r\n\r\n" ..
                    _json,
                    function()
                        SEMAPHORE_TAKEN = false
                        sck:close()
                        sck = nil
                        collectgarbage()
                    end)
            collectgarbage()
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
            sendJSON(json)
            collectgarbage()
        end

        local function respondServerTime()
            sec, usec, clkrate = rtctime.get()
            -- note: usec does only contain actual microseconds after "sec", so its not absolute!
            local first = true
            local json = "{\"server_time\":" .. sec .. "}"
            sendJSON(json)
            collectgarbage()
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
            if string.match(path, "status") then
                respondStatus(sck)
            elseif string.match(path, "timer") then
                respondTimers()
            elseif string.match(path, "servertime") then
                respondServerTime()
            else
                respondRoot(sck, path)
            end
        end

        local function safelyUpdateTimersFromJSON(_json)
            local result = sjson.decode(_json)
            for k,v in pairs(TIMERDEFINITIONS) do
                TIMERDEFINITIONS[k] = nil
            end
            for _timerId, val in pairs(result) do 
                print(" --->>> ")
                addOrUpdateTimer(_timerId, val["from"], val["to"])
                writeTimerConfigToFile()
            end
        end

        local function handlePOST(payload, path)
            if string.match(path, "timers") then
                local _json = string.match(payload, "{.*}")      -- extract JSON from payload
                print(" POST /timers:")
                print(_json)
                safelyUpdateTimersFromJSON(_json)
            end

            respondTimers()
            collectgarbage()
        end
        -- === FUNCTIONS - END ===
    
        -- === ACTUAL EVALUATION ===
        local GET_requestpath = string.match(payload, "GET (.*) HTTP") --or "N/A"
        local POST_requestpath = string.match(payload, "POST (.*) HTTP") --or "N/A"
        
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
