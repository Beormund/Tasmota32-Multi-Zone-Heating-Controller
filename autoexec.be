#------------------------------------------------------------------------------------------------------
  autoexec.be - Berry scripting language
  Copyright (C) 2021 Shaun Brown, Berry language by Guan Wenliang https://github.com/Skiars/berry

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
------------------------------------------------------------------------------------------------------#


# Import heating.be from file system
import heating
# Set the number of heating zones (3 zones by default)
heating.options.zones = 3
# Basic support for I2C LCD 20x4/20x2 display
# Requires display.be to be uploaded to file system
heating.options.use_lcd = true
# Synchronise the relay web toggle button labels
# with the heating controller zone labels 
heating.options.sync_webbuttons = true
# WS2812 pin needs to be configured for LED
# pixel indicator support
heating.options.use_indicators = true
# Eable Tasmota/MQTT "zone" command to change
# power state ofh eating zones
heating.options.use_cmd = true
# Publish MQTT heating zone telemetry
heating.options.use_mqtt = true
# Initialise heating controller
var hc = heating.controller()
# Start the heating controller
hc.start()

