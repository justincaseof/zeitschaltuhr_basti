print("Starting Bootloader...")
button_pin = 0
setupwifi_pin = 2
luafilename = "define_me.lua"
gpio.mode(button_pin, gpio.INPUT)
gpio.mode(setupwifi_pin, gpio.INPUT, gpio.PULLUP)

local startup_interruption = gpio.read(button_pin)
local setup_wifi = gpio.read(setupwifi_pin)
print(" -> startup_interruption: "..((startup_interruption==0 and "yes") or "no"))
print(" -> setup_wifi: "..((setup_wifi==0 and "yes") or "no"))

function normalstart() 
	print("normalstart()")
	luafilename = "timer.lua"
	print(" -> scheduling startup of " .. luafilename)
    tmr.alarm(0, 5000, tmr.ALARM_SINGLE, function() 
            print(" -> starting " .. luafilename)
            dofile(luafilename)
        end
    )
end

function wifisetup() 
	print("wifisetup()")
	luafilename = "wifisetup.lua"
	print(" -> scheduling startup of " .. luafilename)
    tmr.alarm(1, 5000, tmr.ALARM_SINGLE, function() 
            luafilename = "wifisetup.lua"
            print(" -> starting " .. luafilename)
            dofile(luafilename)
            luafilename = "dns-liar.lua"
            print(" -> starting " .. luafilename)
            dofile(luafilename)
        end
    )
end	

if startup_interruption == 0 then
    print(" -> startup_interruption")
elseif setup_wifi == 0 then
	wifisetup()
else
    normalstart()
end
