chip_id = string.format("%06X", node.chipid())
device_id = "esp8266_" .. chip_id
mqtt_prefix = "sensor/" .. device_id
mqttclient = mqtt.Client(device_id, 120)

dofile("config.lua")

i2c.setup(0, 5, 6, i2c.SLOW)
ssd1306 = require("ssd1306")
fn = require("terminus16")
fb = require("framebuffer")
mh_z19 = require("mh-z19")

ledpin = 4
gpio.mode(ledpin, gpio.OUTPUT)
gpio.write(ledpin, 0)

ssd1306.init(128, 32)
ssd1306.contrast(128)
fb.init(128, 32)

no_wifi_count = 0
publish_count = 0
publishing_mqtt = false

function connect_wifi()
	print("Connecting to ESSID " .. station_cfg.ssid)
	wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, wifi_connected)
	wifi.eventmon.register(wifi.eventmon.STA_DHCP_TIMEOUT, wifi_err)
	wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, wifi_err)
	wifi.setmode(wifi.STATION, false)
	wifi.sta.config(station_cfg)
	wifi.sta.connect()
end

function init_mhz19()
	port = softuart.setup(9600, 1, 2)
	port:on("data", 9, uart_callback)
	poll = tmr.create()
	poll:register(5 * 1000, tmr.ALARM_AUTO, query_mhz19)
	poll:start()
	query_mhz19()
	gpio.write(ledpin, 1)
end

function query_mhz19()
	port:write(mh_z19.c_query)
end

function uart_callback(data)
	fb.init(128, 32)

	if not mh_z19.parse_frame(data) then
		fb.print(fn, "MH-Z19 error")
		ssd1306.show(fb.buf)
		return
	end

	local line1 = string.format("%8d ppm\n", mh_z19.co2)
	local line2 = string.format("%8d c\n", mh_z19.temp)

	fb.print(fn, line1)
	fb.print(fn, line2)

	if have_wifi then
		fb.y = 16
		fb.x = 100
		fb.print(fn, string.format("%d", wifi.sta.getrssi()))
	else
		if no_wifi_count == 5 then
			wifi.setmode(wifi.NULLMODE, false)
		end
		if no_wifi_count < 24 then
			no_wifi_count = no_wifi_count + 1
		else
			no_wifi_count = 0
			connect_wifi()
		end
	end
	ssd1306.show(fb.buf)
	fb.init(128, 32)
	publish_count = publish_count + 1
	if have_wifi and publish_count >= 4 and not publishing_mqtt then
		publish_count = 0
		publishing_mqtt = true
		gpio.write(ledpin, 0)
		local json_str = string.format('{"rssi_dbm":%d,"co2_ppm":%d,"temperature_celsius":%d}', wifi.sta.getrssi(), mh_z19.co2, mh_z19.temp)
		mqttclient:publish(mqtt_prefix .. "/data", json_str, 0, 0, function(client)
			publishing_mqtt = false
			gpio.write(ledpin, 1)
			collectgarbage()
		end)
	else
		collectgarbage()
	end
end

function wifi_connected()
	print("IP address: " .. wifi.sta.getip())
	have_wifi = true
	no_wifi_count = 0
	print("Connecting to MQTT " .. mqtt_host)
	mqttclient:on("connect", hass_register)
	mqttclient:on("offline", wifi_err)
	mqttclient:lwt(mqtt_prefix .. "/state", "offline", 0, 1)
	mqttclient:connect(mqtt_host)
end

function wifi_err()
	have_wifi = false
end

function hass_register()
	local hass_device = string.format('{"connections":[["mac","%s"]],"identifiers":["%s"],"model":"ESP8266 + MH-Z19","name":"MH-Z19 %s","manufacturer":"derf"}', wifi.sta.getmac(), device_id, chip_id)
	local hass_entity_base = string.format('"device":%s,"state_topic":"%s/data","expire_after":120', hass_device, mqtt_prefix)
	local hass_co2 = string.format('{%s,"name":"CO₂","object_id":"%s_co2","unique_id":"%s_co2","device_class":"carbon_dioxide","unit_of_measurement":"ppm","value_template":"{{value_json.co2_ppm}}"}', hass_entity_base, device_id, device_id)
	local hass_temp = string.format('{%s,"name":"Temperature","object_id":"%s_temp","unique_id":"%s_temp","device_class":"temperature","unit_of_measurement":"°c","value_template":"{{value_json.temperature_celsius}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)
	local hass_rssi = string.format('{%s,"name":"RSSI","object_id":"%s_rssi","unique_id":"%s_rssi","device_class":"signal_strength","unit_of_measurement":"dBm","value_template":"{{value_json.rssi_dbm}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)

	publishing_mqtt = true
	mqttclient:publish("homeassistant/sensor/" .. device_id .. "/co2/config", hass_co2, 0, 1, function(client)
		mqttclient:publish("homeassistant/sensor/" .. device_id .. "/temperature/config", hass_temp, 0, 1, function(client)
			mqttclient:publish("homeassistant/sensor/" .. device_id .. "/rssi/config", hass_rssi, 0, 1, function(client)
				mqttclient:publish(mqtt_prefix .. "/state", "online", 0, 1, function(client)
					publishing_mqtt = false
					print("Registered with Home Assistant")
					collectgarbage()
				end)
			end)
		end)
	end)
end

print("WiFi MAC: " .. wifi.sta.getmac())
init_mhz19()
connect_wifi()
