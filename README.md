# CO₂ Monitor

This repository contains NodeMCU Lua source code for an [MH-Z19 based CO₂ monitor](https://finalrewind.org/projects/co2-monitor-mhz19-ssd1306/).
It shows the current CO₂ concentration and MH-Z19 temperature on a 128×32 SSD1306 OLED and makes them available to Home Assistant via MQTT.
It can also publish readings to InfluxDB.

## Features

* Display for CO₂ and temperature
* Home Assistant integration via MQTT
* Optional logging to InfluxDB
* Powered via USB

## Components

* Processor: ESP8266
* CO₂ sensor: MH-Z19
* Display: 128×32 OLED via SSD1306 (128×64 also supported with some changes)

## Configuration

WiFi, Home Assistant, and InfluxDB configuration is read from `src/config.lua`.
You will need the following entries.

### WiFi

Assuming ESSID "foo" and PSK "bar".
WPA2 Enterprise is not supported.
Leave out the `psk` for open WiFi.

```lua
station_cfg = {ssid = "foo", pwd = "bar"}
```

### MQTT

The only configurable entity is the hostname of the MQTT broker. The ESP8266
will register itself as `homeassistant/sensor/esp8266_XXXXXX` with the last six
digits representing its WiFi MAC address.

```lua
mqtt_host = "mqtt.example.org"
```

### InfluxDB

These settings are optional. Specify a URL and attributes in order to enable
InfluxDB publishing. For instance, if measurements should be stored as
`mh_z19,location=lounge` in the `sensors` database on
`https://influxdb.example.org`, the configuration is as follows.

```lua
influx_url = 'https://influxdb.example.org/write?db=sensors'
influx_attr = ',location=lounge'
```

You can also use the `esp8266_XXXXXX` device id here, like so:

```lua
influx_url = 'https://influxdb.example.org/write?db=sensors'
influx_attr = ',location=' .. device_id
```

Optionally, you can set `influx_header` to an HTTP header that is passed as
part of the POST request to InfluxDB.

## Images

![](https://finalrewind.org/projects/co2-monitor-mhz19-ssd1306/media/preview.jpg)
