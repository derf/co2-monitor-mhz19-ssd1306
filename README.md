# CO₂ Monitor

This repository contains NodeMCU Lua source code for an [MH-Z19 based CO₂ monitor](https://finalrewind.org/projects/co2-monitor-mhz19-ssd1306/).
It shows the current CO₂ concentration and MH-Z19 temperature on a 128×32 SSD1306 OLED and makes them available to Home Assistant via MQTT.
It can also publish readings to InfluxDB.

## Features

* Display for CO₂ and temperature
* Optional Home Assistant integration via MQTT
* Optional logging to InfluxDB
* Powered via USB

## Components

* Processor: ESP8266
* CO₂ sensor: MH-Z19
* Display: 128×32 OLED via SSD1306 (128×64 also supported with some changes)

## Pinout

* MH-Z19 VCC → NodeMCU 5V
* MH-Z19 GND → NodeMCU/ESP8266 GND
* MH-Z19 RX → NodeMCU D1 (ESP8266 GPIO5)
* MH-Z19 TX → NodeMCU D2 (ESP8266 GPIO4)
* SSD1306 VCC → NodeMCU/ESP8266 3V3
* SSD1306 GND → NodeMCU/ESP8266 GND
* SSD1306 SDA → NodeMCU D5 (ESP8266 GPIO14)
* SSD1306 SCL → NodeMCU D6 (ESP8266 GPIO12)

## Flashing

This repository contains a NodeMCU build that provides the required modules.
You can flash it using e.g. esptool:

```bash
esptool write_flash 0x00000 firmware/nodemcu-release-13-modules-2022-04-17-19-03-07-integer.bin
```

After flashing, the firmware will need a few seconds to initialize the
filesystem. You can use that time to create `config.lua` (see below) and then
flash the Python code, e.g. using nodemcu-uploader:

```bash
ext/nodemcu-uploader/nodemcu-uploader.py upload *.lua
```

Afterwards, you can check whether everything works using the serial connection,
e.g.

```bash
pyserial-miniterm --dtr 0 --rts 0 /dev/ttyUSB0 115200
```

You may need to adjust the `/dev/tty` device name.

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

This setting is optional. Specify the hostname of an MQTT broker in order to
enable MQTT publishing and Home Assistant integration.  The ESP8266 will
register itself as `homeassistant/sensor/esp8266_XXXXXX` with the last six
digits representing its WiFi MAC address.

```lua
mqtt_host = "mqtt.example.org"
```

### InfluxDB

These settings are optional. Specify a URL and attributes in order to enable
InfluxDB publishing. For instance, if measurements should be stored as
`mh_z19,location=lounge` in the `sensors` database on
`http://influxdb.example.org:8086`, the configuration is as follows.

```lua
influx_url = 'http://influxdb.example.org:8086/write?db=sensors'
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

## Resources

Mirrors of this repository are maintained at the following locations:

* [Chaosdorf](https://chaosdorf.de/git/derf/co2-monitor-mhz19-ssd1306)
* [git.finalrewind.org](https://git.finalrewind.org/co2-monitor-mhz19-ssd1306/)
* [GitHub](https://github.com/derf/co2-monitor-mhz19-ssd1306)
