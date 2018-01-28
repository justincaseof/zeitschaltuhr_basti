-- CONSTANTS
local STARTUP_DELAY_MILLIS      = 2000
local FILENAME_APPLICATION      = "timer.lua"
local FILENAME_WIFISETUP        = "wifisetup.lua"

-- VARIABLES --
-- *private*
luafilename                     = "__dummy_lua_filename__"
-- *public*
LED_blue_STATE                  = 1 -- CAN BE USED BY OTHER SCRIPTS TO DEFINE BLUE LED BEHAVIOUR


print("Starting Bootloader...")
button_pin                      = 0 -- = D0 --> the "USER" button on NodeMCU dev kit board, also the red LED (when used as OUTPUT)
setupwifi_pin                   = 1 -- = D1 --> the "FLASH" button on NodeMCU dev kit board
blue_led_pin                    = 4 -- = D4 --> blue LED positioned directly on ESP8266
gpio.mode(button_pin,                   gpio.INPUT)
gpio.mode(setupwifi_pin, gpio.INPUT,    gpio.PULLUP)
gpio.mode(blue_led_pin,                 gpio.OUTPUT)

local startup_interruption = gpio.read(button_pin)
local setup_wifi = gpio.read(setupwifi_pin)
print(" -> startup_interruption: "..((startup_interruption==0 and "yes") or "no"))
print(" -> setup_wifi: "..((setup_wifi==0 and "yes") or "no"))

-- FUNCTION DEFINITIONS --
function normalstart() 
	print("normalstart()")
	luafilename = FILENAME_APPLICATION
	print(" -> scheduling startup of " .. luafilename)
    tmr.alarm(0, STARTUP_DELAY_MILLIS, tmr.ALARM_SINGLE, function() 
            print(" -> starting " .. luafilename)
            dofile(luafilename)
        end
    )
end

function wifisetup() 
	print("wifisetup()")
	luafilename = FILENAME_WIFISETUP
	print(" -> scheduling startup of " .. luafilename)
    tmr.alarm(1, STARTUP_DELAY_MILLIS, tmr.ALARM_SINGLE, function() 
            luafilename = "wifisetup.lua"
            print(" -> starting " .. luafilename)
            dofile(luafilename)
            luafilename = "dns-liar.lua"
            print(" -> starting " .. luafilename)
            dofile(luafilename)
        end
    )
end

-- BLUE LED STATE INDICATION "THREAD" --
-- FIXME: do this with PWM
local timer2_id = 1
local timer2_timeout_millis = 250
local LED_ticks = 0
local LED_blue_STATE_do_toggle = false
local LED_blue_STATE_current = gpio.LOW
tmr.register(timer2_id, timer2_timeout_millis, tmr.ALARM_SEMI, function()
    LED_blue_STATE_do_toggle = false
    if      LED_blue_STATE == 0 then            -- STATE 0:
        gpio.write(blue_led_pin, gpio.HIGH)     --> OFF
    elseif  LED_blue_STATE == 1 then            -- STATE 1:
        gpio.write(blue_led_pin, gpio.LOW)      --> ON
    elseif  LED_blue_STATE == 2 then            -- STATE 2:
        if (LED_ticks % 4) == 0 then            --> SLOW FLASH
            LED_blue_STATE_do_toggle = true
        end
    elseif  LED_blue_STATE == 3 then            -- STATE 3:
        if (LED_ticks % 2) == 0 then            --> FAST FLASH
            LED_blue_STATE_do_toggle = true
        end
    elseif  LED_blue_STATE == 4 then            -- STATE 4:
        LED_blue_STATE_do_toggle = true         --> SUPER FAST FLASH
    else
        print("ILLEGAL LED STATE! RESETTING TO '3'")
        LED_blue_STATE = 3
    end

    -- TOOOOGGGGLLLLEEE --
    if LED_blue_STATE_do_toggle == true then
        if gpio.read(blue_led_pin) == gpio.HIGH then
            gpio.write(blue_led_pin, gpio.LOW)
        else
            gpio.write(blue_led_pin, gpio.HIGH)
        end
    end

    -- INC and RESET
    LED_ticks = LED_ticks +1
    if (LED_ticks > 256) then
        LED_ticks = 0
    end
    tmr.start(timer2_id)    -- restart timer for creating a proper loop
end)

local function startLEDStateTimer()
    tmr.start(timer2_id)
    print(" timer2 started (LED state indication)")
end

-- ACTUAL "MAIN" CODE --
-- CHOOSE 'MODE'
if startup_interruption == 0 then
    print(" -> startup_interruption")
elseif setup_wifi == 0 then
	startLEDStateTimer()
    LED_blue_STATE = 3 -- fast flashing
    wifisetup()
else
    startLEDStateTimer()
    normalstart()
end
