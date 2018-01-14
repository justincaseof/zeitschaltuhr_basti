-- this is a comment
print("Timer")

--------------------------------------------
-- GPIO Setup
--------------------------------------------
print("Setting Up GPIO...")

-- Note: Pin index starts at 0 (for D0 or equivalent pin function)
setupwifi_pin           = 1     --> = D1 ... NOTE: should already have been defined in 'init.lua'
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

-- initially (and permanently) switch on blue LED on ESP8266 board
gpio.write(blue_led_pin, gpio.LOW)
-- initially switch on the relais
switchOn()

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

------------------------
-- timer config stuff --
------------------------
-- Line format: {identifier}:{from}:{to}
print(" #################### ")
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
timerconfigs = {}


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
-- 0: off, 1: on, 2: timer
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
    -- LOG --
    
    print("tick")
    print("  -> relais_state: " .. (relais_state or "?"))
    print("  -> seconds_until_switchoff_counter: " .. (seconds_until_switchoff_counter or "?"))
    print("  -> IP: " .. (wifi.sta.getip() or "?"))
    
    -- railais_state --
    if tonumber(relais_state) == 2 then
        seconds_until_switchoff_counter = seconds_until_switchoff_counter-1
        if seconds_until_switchoff_counter < 0 then 
            relais_state = 0
            seconds_until_switchoff_counter = 0
            switchOff()
        else
            switchOn()
        end
    elseif tonumber(relais_state) == 1 then
        switchOn()
    elseif tonumber(relais_state) == 0 then
        switchOff()
    else
        print(" weird relais_state: " .. relais_state or "nil")
        relais_state = 0
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

    tmr.start(timer1_id)
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
    --print("opening file "..filename.."...")
    if not file.open(filename, "r") then
        sck:close()
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
            else
                sck:close()
            end
        end
    end
    sendChunk()
end

----------------
-- Web Server --
----------------

-- == START ACTUAL WEB SERVER ==
local srv = net.createServer(net.TCP)
srv:listen(80, function(conn)
    conn:on("receive", function(sck, request_payload)
        -- == DATA == --
        local payload = ""
        if request_payload == nil or request_payload == "" then
            payload = ""
        else
            payload = request_payload
        end
        -- ATTENTION: print payload for debugging purposes only!
        --print(payload)

        -- === FUNCTIONS ===
        local function respondMain()
            sck:send("HTTP/1.1 200 OK\r\n" ..
                "Server: NodeMCU on ESP8266\r\n" ..
                "Content-Type: text/html; charset=UTF-8\r\n\r\n", 
                function()
                    Sendfile(sck, "1.html", 
                        function() 
                            sck:send("seconds_until_switchoff_counter: " .. seconds_until_switchoff_counter or "?", 
                            function() 
                                sck:close()
                                sck = nil
                                collectgarbage()
                            end)
                        end)
                end)
        end

        local function respondStatus()
            sck:send("HTTP/1.1 200 OK\r\n" ..
                "Server: NodeMCU on ESP8266\r\n"..
                "Content-Type: application/json; charset=UTF-8\r\n\r\n" ..
                "{\"seconds_until_switchoff_counter\":" .. seconds_until_switchoff_counter .. 
                ",\"relais_state\":" .. relais_state .. "}", 
                function()
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

        local function handleGET(path)
            --print("### handleGET() ###")
            -- path?
            if string.match(path, "status") then
                --print(" - respondStatus()")
                respondStatus(sck)
            else
                --print(" - respondMain()") 
                respondMain(sck)
            end
        end

        -- handle posted data updates
        local function handlePOSTcontent(POST_seconds_until_switchoff_counter, POST_relais_state)
            if POST_seconds_until_switchoff_counter and tonumber(POST_relais_state)==2 then
               seconds_until_switchoff_counter = POST_seconds_until_switchoff_counter
            end

            if POST_relais_state then
                relais_state = POST_relais_state
                -- reset counters
                if tonumber(POST_relais_state)==0 then seconds_until_switchoff_counter = 0 end
                if tonumber(POST_relais_state)==1 then seconds_until_switchoff_counter = 0 end
            end
        end

        local function handlePOST(path)
            --print("### handlePOST() ###")
            -- path?
            if string.match(path, "status") then
                -- POST @ path "/status" --> application/json
                local whitespace1, POST_seconds_until_switchoff_counter = string.match(payload, "\"seconds_until_switchoff_counter\":(%s*)(%d*)")
                local whitespace2, POST_relais_state = string.match(payload, "\"relais_state\":(%s*)(%d)")
                --print("  POST_seconds_until_switchoff_counter: " .. (POST_seconds_until_switchoff_counter or "?"))
                --print("  POST_relais_state: " .. (POST_relais_state or "?"))
                handlePOSTcontent(POST_seconds_until_switchoff_counter, POST_relais_state)
            else
                -- POST @ path "/" --> application/x-www-form-urlencoded
                local POST_seconds_until_switchoff_counter = string.match(payload, "seconds_until_switchoff_counter=(%d*)")
                local POST_relais_state = string.match(payload, "relais_state=(%d)")
                --print("  POST_seconds_until_switchoff_counter: " .. (POST_seconds_until_switchoff_counter or "?"))
                --print("  POST_relais_state: " .. (POST_relais_state or "?"))
                handlePOSTcontent(POST_seconds_until_switchoff_counter, POST_relais_state)
            end
            
            respondMain()
        end
        -- === FUNCTIONS - END ===
    
        -- === ACTUAL EVALUATION ===
        local GET_requestpath = string.match(payload, "GET (.*) HTTP") --or "N/A"
        local POST_requestpath = string.match(payload, "POST (.*) HTTP") --or "N/A"
        --print(" GET_requestpath: " .. (GET_requestpath or "???") )
        --print(" POST_requestpath: " .. (POST_requestpath or "???") )
        
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
