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

past_pos = 1
past = {}

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

	local line1 = string.format("%4d ppm\n", mh_z19.co2)
	local line2 = string.format("%4d c\n", mh_z19.temp)

	past[past_pos] = (mh_z19.co2 - 400) / 64
	past[past_pos] = past[past_pos] >=  0 and past[past_pos] or  0
	past[past_pos] = past[past_pos] <= 31 and past[past_pos] or 31
	past_pos = (past_pos) % 48 + 1

	fb.print(fn, line1)
	fb.print(fn, line2)

	for i = 1, 48 do
		fb.buf[80 + i] = bit.lshift(1, 31 - (past[(past_pos + (i-2)) % 48 + 1] or 0))
	end

	if not have_wifi then
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
			if have_wifi and influx_url and not publishing_http then
				local influx_str = string.format("co2_ppm=%d,temperature_celsius=%d,abc_ticks=%d,abc_count=%d", mh_z19.co2, mh_z19.temp, mh_z19.abc_ticks, mh_z19.abc_count)
				publishing_http = true
				http.post(influx_url, influx_header, "mh_z19" .. influx_attr .. " " .. influx_str, function(code, data)
					gpio.write(ledpin, 1)
					publishing_http = false
					collectgarbage()
				end)
			else
				gpio.write(ledpin, 1)
				collectgarbage()
			end
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
