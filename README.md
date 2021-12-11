# Multi-Zone Heating Controller

## Introduction

This is a multi-zone heating controller written in the Berry scripting language designed to run on an ESP32 microcontroller running the latest Tasmota32.bin development branch firmware.

This heating controller gives independent time control over multiple channels or "zones" (1 zone per relay) on a 7 day weekly programme. Each channel/zone can have any number of programmed on/off schedules. 

## Features

* Multi heating zone support (only limited by the number of relays attached to the ESP32 microcontroller)
* Each heating zone can be programmed using 1 or more schedules
* Schedules and zones can be configured using a custom "Configure Heating" web page
* Custom labels can be specified for each zone
* Individual WS2812 LED pixels can indicate zone status 
* One physical push button per zone is supported with different actions available via single, double and triple press.
* Each zone can be put into manual override. Several manual override modes are available (see Operating Modes below)
* A custom Tasmota "zone" command can be used to turn the zone on/off and switch mode (see below). 
* A custom Tasmota "schedule" command can be used to add/update/delete schedules (see below).
* If Alexa/Hue emulation is enabled, when the power state of the relay is changed via Alexa (or MQTT or by pressing the Tasmota web UI relay buttons) the relevant heating zone's status is synchronised.
* A basic I2C LCD 20x4 screen is supported out of the box. The first line displays date/time; the other 3 lines display on/off times for up to 3 zones.

<img src="screenshots/lcd.jpg" width="400">

### Operating Modes

0. ***Auto Mode*** - zone follows all programmed switching times specified in schedules
1. ***Boost Mode*** - zone turns on for 1 or 2 hours if off or extends time if on, then returns to previous mode
2. ***On Mode*** - zone constantly on irrespective of schedules
3. ***Off Mode*** - zone constantly off irrespective of schedules
4. ***Advance Mode*** - zone brought On if currently Off or Off if currently On until next schedule switching time
5. ***All Day Mode*** - zone operates from first On time until last Off time ignoring switching times in between

It has been tested with the following setup:

## Installation

### 1. Tasmota32 Firmware

Download the latest Tasmota ESP32 development branch firmware from:

<http://ota.tasmota.com/tasmota32/>

This heating controller was tested with Tasmota32.bin 

### 2. Configure Template

Using the Tasmota web UI, navigate to **Configuration | Configure Other**. Paste the following json template into the Template field. Tick "Activate" checkbox and "Save". You may need to adjust the template to match the number of relays you have attached.

```json
{"NAME":"Tasmota ESP32","GPIO":[1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1376,0,640,608,224,0,225,226,32,0,0,0,0,33,34,1,1,1,0,0,1],"FLAG":0,"BASE":1}
```

The above template configures the GPIO pins as follows:

* GPIO19 - WS2812
* GPIO21 - I2C SDA 1
* GPIO22 - I2C SCL 1
* GPIO23 - Relay 1
* GPIO25 - Relay 2
* GPIO26 - Relay 3
* GPIO27 - Button 1
* GPIO32 - Button 2
* GPIO33 - Button 3

Navigate to **Configure Module** and ensure the above template is selected. Restart.

### 3. Configure Tasmota Options

The following backlog commands were executed:

Disable I2C driver 36:

`I2CDriver36 0`

Detach Buttons from Relays

`setoption73 1`

If you intend to use Alexa/Hue emulation, set friendly names for the relays:

`backlog FriendlyName1 Zone 1; FriendlyName2 Zone 2; FriendlyName3 Hot Water; FriendlyName4 $LED; Emulation 2`

If you live in a region with daylight saving you might want to specify a std/dst profile. Check out the Tasmota docs for Timezone, Timestd & Timedst. Here's an example profile for the UK:

`Backlog Timezone 99; timedst 0,0,3,1,1,60; timestd 0,0,10,1,2,0;  Latitude 55; Longitude 0.5`

Don't forget to configure MQTT if you wish to receive Heating Controller telemetry.

### 4. Upload Tasmota Application file (heating.tapp)

Navigate to **Consoles | Manage File system** and upload the following Tasmota Application from the repository:

[heating.tapp](https://github.com/Beormund/Tasmota32-Multi-Zone-Heating-Controller/blob/main/bin/heating.tapp)

Options can be enabled/disabled by using the Configure Heating web page.

## Operation

Navigate to Configuration | Configure Heating to set zone labels, modes, schedules, and options. Or click on the Zone summary info at the top of the Tasmota Home page.

### Zone Command

`zone1` publishes mqtt info for zone 1  
`zone1 1` turns zone 1 on. Valid values are `on|off|1|0|true|false`  

`zone2 {"mode": 0}` switches zone 2 to "Auto" Mode.  
`zone3 {"mode": 1, "hours":2}` switches zone 3 to "Boost" mode. "hours" can be 1 or 2.  
`zone1 {"mode": 2}` switches zone 1 constant on  
`zone2 {"mode": 3}` switches zone 2 constant off  
`zone3 {"mode": 4}` switches zone 3 to Advance mode  
`zone1 {"mode": 5}` switches zone 1 to "All Day" mode.

### Zones command

`zones` publishes mqtt info for all zones

### Schedule Command

`schedule1` publishes mqtt info for schedule1  
`schedule2 {"on":"06:30","zones":[1,1,1],"days":[0,1,1,1,1,1,0],"off":"08:30"}` updates schedule 2  
`schedule3 delete` deletes schedule 3  
`schedule4 {"on":"06:30","zones":[1,1,1],"days":[0,1,1,1,1,1,0],"off":"08:30"}` creates schedule 4 if schedule 3 exists but not schedule 4. i.e., to create a new schedule increment the schedule id.

### Schedules Command

`schedules` publishes mqtt info for all schedules

<img src="./screenshots/tasmota_home.png" width="400">
<img src="./screenshots/manage_heating.png" width="400">
<img src="./screenshots/manage_zone.png" width="400">
<img src="./screenshots/manage_schedule.png" width="400">

3. If physical buttons are configured, each button can operate an associated zone as follows. SINGLE press: zone will toggle from Auto to Advance mode. Auto on switches to Advance off and Auto off switches to Advance on etc. DOUBLE press: Zone switches mode in the following order with each double press: Auto -> All Day -> Const On -> Const Off -> Auto. TRIPLE press: mode switches from Auto to Boost (1 hour), or if boost is activated, from Boost to Auto.
4. Ensure that schedule on/off times do not overlap as this may result in unexpected behaviour.
5. If there is a power cut or the microcontroller is restarted, zones will be restored to their last operating mode.
6. If you have an MQTT broker, the following is an example payload that the heating controller publishes when a zone changes state:

```yaml
17:00:01.609 MQT: wifi2mqtt/Heating-Controller3/tele/RESULT = `{"Heating":{"Mode":"Auto","Zone":3,"Until":"22:30 Sun 31 Oct 21","Power":"On","Label":"HWTR"}}`
```

## Known Issues

The scripts are large and if PSRAM is not present the heap may decrease to a point where the web UI becomes sluggish.

## Planned Enhancements

Tasmota Berry now has native support for WS2812 so the pixel indicator functionality will be reworked to make use of this new feature.

