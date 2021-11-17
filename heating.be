#  ------------------------------------------------------------------------------------------------------
#  heating.be - Berry scripting language
#  Copyright (C) 2021 Shaun Brown, Berry language by Guan Wenliang https://github.com/Skiars/berry
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#  ------------------------------------------------------------------------------------------------------

import string
import json
import webserver

var heating = module('heating')

# All tasmota api calls are accessed via tasmota_api
class tasmota_api
    def strftime(format, secs)
        return tasmota.strftime(format, secs)
    end
    def rtc()
        return tasmota.rtc()
    end
    def time_dump(secs)
        return tasmota.time_dump(secs)
    end
    def now()
        var l = self.rtc()['local']
        var t = self.time_dump(l)
        var sfm = t['hour']*3600+t['min']*60+t['sec']
        t.setitem('sfm', sfm)
        t.setitem('local', l)
        return t
    end
    def tomorrow(day)
        var wd = day != nil ? day : self.now()['weekday']
        return wd < 6 ? wd+1 : 0
    end
    def cmd(text)
        return tasmota.cmd(text)
    end
    def log(text)
        tasmota.log(text)
    end
    def set_timer(millis, func, id)
        tasmota.set_timer(millis, func, id)
    end
    def remove_timer(id)
        tasmota.remove_timer(id)
    end
    def set_power(zone, power)
        if tasmota.get_power()[zone] != power
            tasmota.set_power(zone, power)
        end
    end
    def add_rule(trigger, func)
        tasmota.add_rule(trigger, func)
    end
    def add_cmd(cmd, func)
        tasmota.add_cmd(cmd, func)
    end
    def resp_cmnd(payload)
        tasmota.resp_cmnd(payload)
    end
    def publish_result(payload)
        tasmota.publish_result(payload, '')
    end
    def get_persist()
        import persist
        return persist
    end
end

heating.api = tasmota_api()

class options
    # If true the heating module will try to load display.be and use an attached i2c LCD display
    static use_lcd = false
    # Enables a zone command to turn zones on/off via console and MQTT etc
    static use_cmd = false
    # Enables addressable LED indicator lights to be set using util.mode_colors
    static use_indicators = false
    # If true the Tasmota home page relay toggle buttons will be renamed and kept in sync with zone names
    static sync_webbuttons = false
    # publish events to MQTT
    static use_mqtt = false
    # Number of heating zones (e.g., ZN1, ZN2, ZN3). Set zone names using the 'Configure Heating' page
    static zones = 3
end

heating.options = options

class util
    # Weekday names. Sun = 0, Sat = 6
     static days = [
        'Sun', # 1 << 0
        'Mon', # 1 << 1
        'Tue', # 1 << 2
        'Wed', # 1 << 3
        'Thu', # 1 << 4
        'Fri', # 1 << 5
        'Sat'  # 1 << 6
    ]
    # ---------------------------------------------------------------------------------------------------
    # Auto:  zone follows all programmed switching times specified in schedules 
    # Boost: zone turns on for 1 or 2 hours if off or extends time if on, then returns to previous mode
    # On:    zone constantly on irrespective of schedules
    # Off:   zone constantly off irrespective of schedules
    # Adv:   zone brought On if currently Off or Off if currently On until next schedule switching time
    # Day:   zone operates from first On time until last Off time ignoring switching times in between
    # ---------------------------------------------------------------------------------------------------
    static modes = [
        'Auto', # 0
        'Boost', # 1
        'On', # 2
        'Off', # 3
        'Adv', # 4
        'Day' # 5
    ]
    # Set indicator color for each mode
    static colors = [
        '00FF00', # Green
        '800080', # Purple
        '088F8F', # Dark Cyan
        'FF00FF', # Magenta
        '0000FF', # Blue
        'FFFF00'  # Yellow
    ]
    # Settings are retrieved from persist. Call config.load() to hydrate schedules and zones
    static settings = heating.api.get_persist()
    # LCD display. See screen class for further details. HeatingController initialises the display
    static lcd = nil
    # Enable easy access to config. HeatingController initialises the config.
    static config = nil
    # Enable access to override capability. HeatingController initialises.
    static override = nil
end

# Used to load html.json from the file system 
class file
    def load(fn)
        import path
        var obj, f
        if path.exists(fn)
            try
                f = open(fn, 'r')
                obj = json.load(f.read())
                f.close()
            except .. as e, m
                if f != nil f.close() end
                raise e, m
            end
        end
        return obj
    end
end

# If heating.options.use_screen is set this class loads the display.be driver
class screen
    var lcd
    def init()
        import display
        self.lcd = display.lcd_i2c()
    end
    def power(bool)
        self.lcd.set_backlight(bool)
    end
    def update_clock()
        var ls = heating.api.rtc()['local']
        self.lcd.write_line(heating.api.strftime('%H:%M %a %d %b %y', ls), 1)
    end
    def print(line, text)
        self.lcd.write_line(text, line)
    end
    def clear_line(line)
        self.lcd.write_line('', line)
    end
    def clear_screen()
        self.lcd.clear()
    end
end

# A status contains information about the current state of a zone
class status
    var zone, mode, power, expiry
    # @param zone: index of zone from util.settings.zones
    # @param mode: which mode the zone is currently set to
    # @param power: on/off state of zone
    # @param expiry: next on/off time for auto or expiry for boost
    def init(zone, mode, power, expiry)
        self.zone = zone
        self.mode = mode
        self.power = power
        self.expiry = expiry
    end
    # Display max 20 chars: e.g., 'HTG1 off until 16:30'
    def set_lcd()
        if !util.lcd return end
        var message = self._call(false, '%s %s until %s')
        util.lcd.print(self.zone+2, message) 
    end
    # WS2812 LED (1 pixel per zone) indicator
    def set_led()
        if !heating.options.use_indicators return end
        var led = 'Led' .. self.zone+1
        var color = self.power ? util.colors[self.mode] : 'FF0000'
        heating.api.cmd(string.format('%s #%s', led, color))
    end
    # Publish this status as an MQTT message
    def pub_mqtt()
        if !heating.options.use_mqtt return end
        heating.api.publish_result(json.dump(self._tomap()))
    end
    # Log info with the BRY: prefix
    def log_info()
        heating.api.log('BRY: ' .. self.get_info())
    end
    # E.g., 'HTG1 Auto off until 16:30 Mon 18 Oct 21'
    def get_info()
        return self._call(true, '%s %s %s until %s',  util.modes[self.mode])
    end
    # Update logs, LED, MQTT and LCD screen
    def notify()
        self.log_info()
        self.set_led()
        self.pub_mqtt()
        self.set_lcd()
    end
    # Short time: 16:30; Detailed time: 16:30 Mon 18 Oct 21
    def _getdt(secs, detailed)
        return detailed 
            ? heating.api.strftime('%H:%M %a %d %b %y', secs)
            : heating.api.strftime('%R', secs)
    end
    # Calls string.format with varying args
    def _call(d, *args)
        var label = util.settings.zones.get_label(self.zone)
        var power = self.power ? 'on' : 'off'
        if self.mode == 2 || self.mode == 3
            return string.format('%s Const %s', label, power)
        else
            args.insert(1, label)
            args.push(power)
            args.push(self._getdt(self.expiry, d))
            return call(string.format, args)
        end
    end
    # Helper map for self.pub_mqtt()
    def _tomap()
        return {
            "Heating": {
                "Zone": self.zone + 1,
                "Label": util.settings.zones.get_label(self.zone),
                "Mode": util.modes[self.mode],
                "Power": self.power ? 'On' : 'Off',
                "Until": self._getdt(self.expiry, true)
            }
        }
    end
end

# This class represents a single heating zone
# zone['l'] = label
# zone['e'] = expiry
# zone['m'] = mode (6 bit for previous & current)
# zone['p'] = power (2 bit for auto & override)
class zone: map
    static label = 'l', expiry = 'e', mode = 'm', power = 'p'
    def init(o)
        super(self).init()
        o = isinstance(o, map) ? o : {"l": o ,"e": 0, "m": 0, "p": 0}
        for k: o.keys()
            self[k] = o[k]
        end
    end
end

# A collection of zones
class zones: list
    def init(l)
        super(self).init()
        if isinstance(l, list)
            for z: l
                self.push(zone(z))
            end
        end
    end    
    # Returns a zone's power state 
    def get_power(z, m)
        return !!((self[z][zone.power] >> int(!m)) & 1)
    end
    # Sets a zone's power state
    def set_power(z, p, m)
        self[z][zone.power] ^= (-int(p) ^ 
        self[z][zone.power]) & (1 << int(!m)) 
        if m == 0
            self[z][zone.power] &= ~(1 << 0)
        end
    end
    # Gets the mode for a given zone
    def get_mode(z, p)
        var lsb = p ? 3 : 0, msb = lsb + 2
        return (self[z][zone.mode] >> lsb) & ~(~0 << (msb-lsb+1))
    end
    # Set the mode for a given zone
    def set_mode(z, m)
        var current = self.get_mode(z)
        if current != m
            self[z][zone.mode] = current << 3
            self[z][zone.mode] += m
        end
    end
    # Configures a new zone and adds it to the list of zones
    def add_zone(l)
        self.push(zone(l))
    end
    # Sets a zone's mode, power and expiry
    def set_zone(z, m, p, e)
        self.set_mode(z, m)
        self.set_power(z, p, m)
        if e
            self.set_expiry(z, e)
        end
    end
    # Gets the custom name for the zone
    def get_label(z)
        return self[z][zone.label]
    end
    # Sets a custom name for a zone
    def set_label(z, l)
        self[z][zone.label] = l
    end
    # Gets the next run time or expiry in seconds for a zone
    def get_expiry(z)
        return self[z][zone.expiry]
    end
    # Sets a zone's next run time or expiry time
    def set_expiry(z, e)
        self[z][zone.expiry] = e
    end
    def get_status(z)
        var m = self.get_mode(z)
        var p = self.get_power(z, m)
        var e = self.get_expiry(z)
        return status(z, m, p, e)
    end
end

# A schedule can specify switching times for 1 or more zones
# Schedules can be created/edited/deleted using the Configure Heating page
# schedule['i'] = id
# schedule['1'] = "On" time in seconds from midnight
# schedule['0'] = "Off" time in seconds from midnight
# schedule['d'] = Days (Sun = 1 << 0, Mon = 1 << 1 etc)
# schedule['z'] = Zones (ZN1 = 1 << 0, ZN2 = 1 << 1 etd)
class schedule: map
    static on = '1', off = '0', id = 'i', days = 'd', zones = 'z'
    def init(m)
        super(self).init()
        m = isinstance(m, map) ? m : {"i":0, "1":0, "0":0, "d":0, "z":0}
        for k: m.keys()
            self[k] = m[k]
        end
    end
    # true if index of list is in bitsum
    def is_set(k, i)
        return self[k] & (1 << i) ? true : false
    end
    # Converts a string time to seconds from midnight
    # E.g., 10:15 -> 10x3600 + 15x60 
    def str2secs(str)
        var hours = int(str[0..1])
        var mins = int(str[3..])
        return hours*3600+mins*60
    end
    # Converts 36000 to "10:00"
    def secs2str(secs)
        var hours = (secs/60)/60
        var mins = (secs/60)%60
        return string.format('%02d:%02d', hours, mins)
    end
    # Calculates the next on/off run time in seconds
    def get_runat(_t)
        if !self[self.days] return 0 end
        var t = self[_t] # _t is '1' (on) or '0' (off)
        var now = heating.api.now()
        var sfm = now['sfm'] # Now as secs from midnight
        var wd = now['weekday'] # Today [0 .. 6]
        var i = t <= sfm ? 1 : 0 # Has on/off time past?
        var day = i ? heating.api.tomorrow(wd) : wd 
        while !self.is_set(self.days, day) i+=1
            day = heating.api.tomorrow(day)            
        end
        return ( i ? 86400*i-(sfm-t) : t-sfm) + now['local']
    end
    # Calculates if the current schedule is on or off
    def is_running(zone)
        var n = heating.api.now()
        var sfm = n['sfm']
        if self.is_set(self.days, n['weekday'])
            if zone != nil && !self.is_set(self.zones, zone)
                return false
            end
            if self[self.on] <= sfm && sfm < self[self.off]
                return true
            end            
        end
        return false
    end
    # Does this instance of schedule = another instance?
    def == (o)
        for k: self.keys()
            if self[k] != o[k]
                return false
            end
        end
        return true
    end
    def != (o)
        return !self==(o)
    end
end

# List of all schedules
class schedules : list
    def init(l)
        super(self).init()
        if isinstance(l, list)
            for s: l
                self.push(schedule(s))
            end
        end
    end
    # list.push overridden to take a schedule
    def push(schedule)
        schedule[schedule.id] = self.next_id()
        super(self).push(schedule)
    end
    # list.pop overridden to remove schedule by id
    def pop(id)
        for s: 0 .. self.size()-1
            if self[s][schedule.id] == id
               super(self).pop(s)
               break 
            end
        end
        self.reindex()
    end
    # Convenience method to get a schedule by id
    def get(id)
        for s: self
            if s[s.id] == id
                return s
            end
        end
    end
    # Updates a schedule using schedule param
    def update(updated)
        var current = self.get(updated[updated.id])
        if current && current == updated
            return false
        end
        for k: current.keys()
            current[k] = updated[k]
        end
        return true
    end
    # Get a status object for the next schedule
    def get_next_status(zone)
        import math
        var i = math.imax
        for s: self
            if s.is_set(s.zones, zone)
                var p = s.is_running(zone)
                var r = s.get_runat(p ? s.off : s.on)
                if p 
                    return status(zone, 0, true, r)
                else 
                    i = r < i ? r : i 
                end
            end
        end
        return status(zone, 0, false, i)
    end
    # Gets the schedule with the earliest on time for day
    def get_first_on(zone, day)
        var f = / a,b -> a[a.on] < b[b.off]
        return self.get_day_onoff(zone, f, day)
    end
    # Gets the schedule with the latest off time for day
    def get_last_off(zone, day)
        var f = / a,b -> a[a.off] > b[b.off]
        return self.get_day_onoff(zone, f, day)
    end
    # Returns the first on and last off schedules for day
    def get_daytime(zone, day)
        return {
            "start": self.get_first_on(zone, day), 
            "finish": self.get_last_off(zone, day)
        }
    end
    # Gets the next day's first on schedule
    def get_next_first_on(zone, day)
        return self.get_first_on(zone, heating.api.tomorrow(day))
    end
    # Retrieves the first on or last off schedule for day
    def get_day_onoff(zone, f, day)
        if self.size() == 0 return end
        var wd = day != nil ? day : heating.api.now()['weekday']
        var l = 0, t = nil
        while (l < 7 && !t) l+=1 
            for s: self
                if s.is_set(s.zones, zone) && s.is_set(s.days, wd)
                    t = !t ? s : t
                    t = f(s,t) ? s : t
                end
            end
            wd = heating.api.tomorrow(wd)
        end
        return t
    end
    # Gets the next free id for new schedules
    def next_id()
        return self.size()+1
    end
    # Used to reset all schedule ids when list changes
    def reindex()
        for i: 0 .. self.size()-1
            self[i][schedule.id] = i+1
        end
    end
end

# Configures zones, schedules and labels
class config
    def get_next_status(zone)
        if util.settings.zones.get_mode(zone)
            # Return a zone status if mode is in override
            return util.settings.zones.get_status(zone)
        else
            # Return a schedule status if mode is auto
            return util.settings.schedules.get_next_status(zone)
        end
    end
    # If sync_webbuttons is true set the relay toggle button to label
    def set_webbutton(btn, label)       
        heating.api.cmd(string.format('webbutton%d %s', btn, label))
    end
    # Saves the configuration to _persist.json
    def save()
        util.settings.save()
    end
    # Loads zones and schedules from _persist.json
    # If _persist.json does not contain the data default
    # zones and schedules are created.
    def load()
        if util.settings.has('zones')
            # Need to convert from a list to zones sub-class
            util.settings.zones = zones(util.settings.zones)
        else
            util.settings.zones = zones()
            for i: 1 .. heating.options.zones
                util.settings.zones.add_zone('ZN' .. i)
            end
        end
        if util.settings.has('schedules')
            # Need to convert from a list to schedules sub-class
            util.settings.schedules = schedules(util.settings.schedules)
        else
            var sum = (1 << heating.options.zones)-1
            # Four initial schedules are created AM & PM for weekdays & w/e
            # 62 = Mon-Fr; 65 = Sat/Sun
            util.settings.schedules = schedules([
                {"i": 1, "1": 23400, "0": 30600, "d": 62, "z": sum},
                {"i": 2, "1": 59400, "0": 79200, "d": 62, "z": sum},
                {"i": 3, "1": 27000, "0": 37800, "d": 65, "z": sum},
                {"i": 4, "1": 61200, "0": 82800, "d": 65, "z": sum}
            ])
        end
        # If heating.options.zones is set to a number of zones
        # that is different to _persist.json then resize zones
        var diff = util.settings.zones.size() - heating.options.zones
        if diff > 0 # Need to truncate...
            util.settings.zones.resize(heating.options.zones)
            for s: util.settings.schedules
                s[s.zones] = s[s.zones] >> diff
            end
        elif diff < 0 # Need to append
            for i: util.settings.zones.size()+1 .. heating.options.zones
                self.settings.zones.add_zone('ZN' .. i)
                for s: util.settings.schedules
                    s[s.zones] = (s[s.zones]<<diff)|((1<<diff)-1)
                end
            end
        end
    end
end

# This class is responsible for setting timers - 1 for each schedule
# A timer is set for the on time and reset to the off time when it pops.
class scheduler
    var running
    def init()
        self.running = false
    end
    def start()
        for s: util.settings.schedules
            self.set_timer(s)
        end
        self.on_start()
    end
    def stop()
        self.running = false
        heating.api.remove_timer('schedule')
    end
    def set_timer(s)
        # Get the time now in seconds
        var now = heating.api.rtc()['local']
        # Is the schedule switching on or off?
        var power = s.is_running()
        # Get the next run time depending on power state
        var runat = s.get_runat(power ? s.off : s.on)
        # Timers are set in millis (add 1 second safety margin)
        var millis = (runat+1 - now) * 1000
        # Call on_pop when the timer expires
        heating.api.set_timer(millis, / -> self.on_pop(s), 'schedule')
    end
    # This method is only used when the scheduler is first run.
    # It retrieves statuses for next auto mode run times
    def on_start()
        self.running = true
        for z: 0 .. util.settings.zones.size()-1
            if util.settings.zones.get_mode(z)
                # If mode is override set schedule power state
                var power = util.settings.schedules.get_next_status(z).power
                util.settings.zones.set_power(z, power)
            else
                # Set power states and display/log schedule status
                self.on_completed(z)
            end
        end
    end
    # Called when a schedule on or off time expires/completes
    def on_pop(s)
        if !self.running return end
        # Get the power state for the schedule
        var power = s.is_running()
        # Check each zone for the schedule
        for zone: 0 .. util.settings.zones.size()-1
            # Is the zone set for this schedule?
            if !s.is_set(s.zones, zone) continue end
            # What mode is the zone in?
            var mode = util.settings.zones.get_mode(zone)
            if mode == 0 # Auto
                self.on_completed(zone)
            elif mode == 4 # Advance
                # If previous mode was Day switch back to Day mode, else Auto
                var previous = util.settings.zones.get_mode(zone, true) == 5 ? 5 : 0
                # Update zone configuration state
                util.settings.zones.set_zone(zone, previous, power)
                self.on_completed(zone)
            elif mode == 5 # Daytime
                # If schedule matches first on/last off, update power, expriry etc
                if util.override.check_day(zone, s, power) 
                    self.on_completed(zone)
                end
                # Update schedule power
                util.settings.zones.set_power(zone, power)
            end
        end
        # Force the updated configuration to be saved to flash
        util.config.save()
        # Set the schedule's next switching timer
        self.set_timer(s)
    end
    def on_completed(zone)
        var stat = util.config.get_next_status(zone)
        # Update the power and expiry/next run time for the zone
        util.settings.zones.set_zone(zone, stat.mode, stat.power, stat.expiry)
        # Set the power state of the relay
        heating.api.set_power(zone, stat.power)
        # Update logs, LED, MQTT and LCD screen
        stat.notify()
    end
end

# Used to create timers for override boost and minute ticker for displaying time
class clock
    var repeat
    def init(r)
        self.repeat = r != nil ? r : true
    end
    def start(h, f, id)
        self.tick(h, f, id)
    end
    def tick(h, f, id)
        heating.api.set_timer(
            f(heating.api.now()), 
            / -> self.pop(h, f, id)
            , id
        )
    end
    def pop(h, f, id)
        h()
        if !self.repeat return end
        self.tick(h, f, id)
    end
end

# This class handles the manual override of scheduling
class override
    var clocks
    def init()
        self.clocks = {}
    end
    # Set the override mode for a given zone
    def set(zone, mode, duration)
        var director = [
            self.auto,
            self.boost,
            self.on,
            self.off,
            self.advance,
            self.day
        ]
        self.check_boost(zone, mode)
        director[mode](self, zone, duration)
        self.on_completed(zone)
    end
    # Before the mode is changed, check if we need to cancel a running boost
    def check_boost(zone, mode)
        var current = util.settings.zones.get_mode(zone)
        var id = 'boost' .. zone
        if mode != current && current == 1 && self.clocks.find(id)
            self.on_boost_cancel(zone)
        end
    end
    # Set the relay power state and log/display message for zone
    def on_completed(zone)
        var stat = util.settings.zones.get_status(zone)
        heating.api.set_power(zone, stat.power)
        # Update logs, LED, MQTT and LCD screen
        stat.notify()
        # Force the updated configuration to be saved to flash
        util.config.save()
    end
    # turn zone on if off for duration or extend time if on.
    def boost(zone, secs)
        var id = 'boost' .. zone
        var h = / -> self.on_boost_end(zone)
        var f = / -> !secs ? 3600000 : secs * 1000
        var repeat = false
        self.clocks[id] = clock(repeat)
        self.clocks[id].start(h, f, id)
        var expiry = (!secs ? 3600 : secs) + heating.api.rtc()['local']
        util.settings.zones.set_zone(zone, 1, true, expiry)
    end
    # Called by boost handler when timer completes
    def on_boost_end(zone)
        self.on_boost_cancel(zone)
        self.set(zone, util.settings.zones.get_mode(zone, true))
    end
    # Called when boost timer is active but mode is changed
    def on_boost_cancel(zone)
        var id = 'boost' .. zone
        heating.api.remove_timer(id)
        self.clocks.remove(id)
        util.settings.zones.set_power(zone, false, true)
        util.settings.zones.set_expiry(zone, 0)
        heating.api.log(string.format(
            'BRY: %s boost off', 
            util.settings.zones.get_label(zone))
        )
    end
    # Toggle zone state
    def advance(zone)
        var stat = util.settings.schedules.get_next_status(zone)
        util.settings.zones.set_zone(zone, 4, !stat.power, stat.expiry)
    end
    # Swtich zone to timer mode
    def auto(zone)
        var stat = util.settings.schedules.get_next_status(zone)
        util.settings.zones.set_zone(zone, 0, stat.power, stat.expiry)
    end
    # Switch zone permanently on
    def on(zone)
        util.settings.zones.set_zone(zone, 2, true)
    end
    # Switch zone permanently off
    def off(zone)
        util.settings.zones.set_zone(zone, 3, false)
    end
    # Switch zone on from first 'ON' time until last 'OFF' time 
    def day(zone, _dt)
        var dt = _dt ? _dt : util.settings.schedules.get_daytime(zone)
        var start = dt['start'], finish = dt['finish']
        if !start || !finish 
            self.set(zone, 0)
            return
        end
        var n = heating.api.now()
        var on = start.get_runat(start.on)
        var off = finish.get_runat(finish.off)
        var power = (on > off || on <= n['local']) && n['local'] <= off
        var expiry
        if power expiry = off
        elif n['sfm'] < start[start.on] expiry = on
        elif n['sfm'] > finish[finish.off]
            var nfo = util.settings.schedules.get_next_first_on(zone, n['weekday'])
            expiry = nfo.get_runat(nfo.on)
        end
        util.settings.zones.set_zone(zone, 5, power, expiry)
    end
    # Used by scheduler to test if schedule matches day first on or last off time
    def check_day(zone, s, power)
        var dt = util.settings.schedules.get_daytime(zone)
        var start = dt['start'], finish = dt['finish']
        if power ? start[start.id] == s[s.id] : finish[finish.id] == s[s.id]
            self.day(zone, dt)
            return true
        end
    end
    # Refresh overrides for all zones on re-start or schedule/zone changes.
    def refresh()
        for zone: 0 .. util.settings.zones.size()-1
            var mode = util.settings.zones.get_mode(zone)
            if mode == 1 && !self.clocks.find('boost' .. zone)
                var expiry = util.settings.zones.get_expiry(zone) - heating.api.rtc()['local']
                self.set(zone, mode, expiry)
            elif mode  > 1
                self.set(zone, mode)
            end
        end
    end
end

# Display Schedule Summary/Editor in 'Configure Heating'
class ScheduleGUI
    # Get list of day indices
    # bits 30 -> [1,2,3,4]
    def bits2days(bits)
        var l = []
        for d: 0 .. util.days.size()-1
            if bits & (1 << d)
                l.push(d)
            end
        end
        return l
    end
    # Groups consecutive days together
    # [0,1,3,4,5] -> [[0, 1], [3, 4, 5]]
    def group_days(days)
        var run = []
        var result = [run]
        var expect = nil
        for v: days
            if v == expect || expect == nil
                run.push(v)
            else
                run = [v]
                result.push(run)
            end
            expect = v + 1
        end
        return result
    end
    # Takes groups of days and turns them into ranges
    # [[0, 1], [3, 4, 5]] -> "Sun-Mon, Wed-Fri"
    def concat_days(groups)
        var result = ''
        for i: 0 .. groups.size()-1
            var g = groups[i]
            result += util.days[g[0]]
            if g.size()>1
                result += '-' + util.days[g[g.size()-1]]
            end
            if i < groups.size()-1
                result += ','
            end
        end
        if result == 'Sun,Sat' result = 'Sat/Sun' end
        return result
    end
    # Send a list of schedules as HTML fragment
    def show_schedules(html)
        webserver.content_send(html[0])
        for s: util.settings.schedules
            var day_indices = self.bits2days(s[s.days])
            var grouped_days = self.group_days(day_indices)
            var day_str = self.concat_days(grouped_days)
            var zone_str = ''
            for z: 0 .. util.settings.zones.size()-1
                if !s.is_set(s.zones, z) continue end
                zone_str += util.settings.zones.get_label(z)
                if z < util.settings.zones.size()-1
                    zone_str += ' '
                end
            end
            webserver.content_send(
                string.format(
                    html[1], s[s.id], s[s.id], s.secs2str(s[s.on]), 
                    s.secs2str(s[s.off]), day_str, zone_str
                )
            )
        end
        var new_id = util.settings.schedules.next_id()
        webserver.content_send(string.format(html[2], new_id ))
    end
    # Displays a web control for editing a single schedule
    def show_editor(id, html)
        var ss = util.settings.schedules
        var s = ss.get(id)
        var action = s ? 'update' : 'new'
        s = s ? s : schedule()
        webserver.content_send(string.format(html[0], id, s.secs2str(s[s.on]), s.secs2str(s[s.off])))
        for d: 0 .. util.days.size()-1
            var checked = s.is_set(s.days, d) ? 'checked' : ''
            var dl = util.days[d]
            webserver.content_send(string.format(html[1], dl, 1 << d, checked, dl, dl))
        end
        webserver.content_send(html[2])
        for z: 0 .. util.settings.zones.size()-1
            var checked = s.is_set(s.zones, z) ? 'checked' : '', zl = util.settings.zones.get_label(z)
            webserver.content_send(string.format(html[3], zl, 1 << z, checked, zl, zl))
        end
        webserver.content_send(string.format(html[4], action, id))
        if action == 'update'
            webserver.content_send(string.format(html[5], id))
        end
        webserver.content_send(html[6])
    end
end

# Displays zone sumarry/editor widgets in 'Configure Heating'
class ZoneGUI
    # Shows a list of zones with status info
    def show_zones(html)
        webserver.content_send(html[0])
        for z: 1 .. util.settings.zones.size()
            var info = util.settings.zones.get_status(z-1).get_info()
            webserver.content_send(
                string.format(html[1], z, z, info)
            )
        end
        webserver.content_send(html[2])
    end
    # Displays a web control for editing a single zone
    def show_editor(zid, html)
        var label = util.settings.zones.get_label(zid-1)
        webserver.content_send(string.format(html[0], zid, label))
        for k: 0 .. util.modes.size()-1
            var checked = util.settings.zones.get_mode(zid-1) == k ? 'checked' : ''
            var mode = util.modes[k]
            webserver.content_send(string.format(html[1], mode, k, checked, mode, mode))
        end
        webserver.content_send(html[2])
        webserver.content_send(string.format(html[3], zid-1))
    end
end

# HTTP driver for "Configure Heating" page
class WebManager : Driver
    var controller, restart, html, button
    def init(restart)
        self.restart = restart
        self.html = file().load('html.json')
        self.button = self.html['button']
        self.html = nil
    end
    # Displays a "Configure Heating" button on the configuration page
    def web_add_config_button()
        webserver.content_send(self.button)
    end
    # Hydrate a schedule object for a new/update action
    def fill_schedule(id, s)
        s[s.id] = id
        for arg: 0 .. webserver.arg_size()-2
            var name = webserver.arg_name(arg)
            var value = webserver.arg(arg)
            if name == 'days[]'
                s[s.days] += int(value)
            elif name == 'zones[]'
                s[s.zones] += int(value)
            elif name == 'on'
                s[s.on] = s.str2secs(value)
            elif name == 'off'
                s[s.off] = s.str2secs(value)
            end
        end           
    end
    # Updates a zone based on web form entry
    def update_zone()
        var id = int(webserver.arg('zone'))
        if webserver.has_arg('label')
            var label = webserver.arg('label')
            if size(label) > 0 && label != util.settings.zones.get_label(id)
                util.settings.zones.set_label(id, label)
                # Update the display to reflect the new label
                if util.lcd
                    util.settings.zones.get_status(id).set_lcd()
                end
                # Sync webbuttons if option set
                if heating.options.sync_webbuttons
                    util.config.set_webbutton(id+1, label)
                end
            end
        end
        if webserver.has_arg('modes[]')
            var mode = int(webserver.arg('modes[]'))
            if mode != util.settings.zones.get_mode(id)
                if mode == 1
                    if webserver.has_arg('hours[]')
                        var hours = int(webserver.arg('hours[]'))
                        util.override.set(id, mode, hours * 3600)
                    end
                else
                    util.override.set(id, mode)
                end
            end
        end
    end
    # Deletes/Updates/Creates a schedule based on web form entry
    def update_schedule()
        if webserver.has_arg('delete')
            var id = int(webserver.arg('delete'))
            util.settings.schedules.pop(id)
            return true
        elif webserver.has_arg('update')
            var id = int(webserver.arg('update'))
            var schedule = schedule()
            self.fill_schedule(id, schedule)
            return util.settings.schedules.update(schedule)
        elif webserver.has_arg('new')
            var id = int(webserver.arg('new'))
            var schedule = schedule()
            self.fill_schedule(id, schedule)
            util.settings.schedules.push(schedule)
            return true
        end
    end
    # This HTTP GET manager controls which web controls are displayed
    def page_heating_mgr()
        if !webserver.check_privileged_access() return nil end
        if !self.html self.html = file().load('html.json') end
        webserver.content_start('Configure Heating')
        webserver.content_send_style()
        if webserver.has_arg('id')
            var gui = ScheduleGUI()
            gui.show_schedules(self.html['sched-sum'])
            gui.show_editor(int(webserver.arg('id')), self.html['sched'])
        elif webserver.has_arg('zid')
            var gui = ZoneGUI()
            gui.show_zones(self.html['zone-sum'])
            gui.show_editor(int(webserver.arg('zid')), self.html['zone'])
        else
            ZoneGUI().show_zones(self.html['zone-sum'])
            ScheduleGUI().show_schedules(self.html['sched-sum'])
        end
        webserver.content_button(webserver.BUTTON_CONFIGURATION)
        webserver.content_stop()
        self.html = nil
    end
    # This HTTP POST manager handles the submitted web form data
    def page_heating_ctl()
        if webserver.has_arg('zone')
            self.update_zone()
        elif self.update_schedule()
            var rc = self.restart
            rc()
        end
        self.page_heating_mgr()
        # Force the updated configuration to be saved to flash
        util.config.save()
    end
    # Add HTTP POST and GET handlers
    def web_add_handler()
        webserver.on('/hm', / -> self.page_heating_mgr(), webserver.HTTP_GET)
        webserver.on('/hm', / -> self.page_heating_ctl(), webserver.HTTP_POST)
    end
end

# The main class for setting up the heating controller
class HeatingController
    var ticker, scheduler, web_manager
    def init()
        # Create the configuration capability
        util.config = config()
        # Load persisted label, zone and schedule data
        util.config.load()
        # If sync_webbuttons is set, update relay toggle buttons
        if heating.options.sync_webbuttons
            for z: 0 .. util.settings.zones.size()-1
                util.config.set_webbutton(z+1, util.settings.zones.get_label(z))
            end
        end
        # If use_lcd is set, create a minute ticker to display the time
        if heating.options.use_lcd
            util.lcd = screen() 
        end
        # Create the override capability
        util.override = override()
        # Create the scheduler capability
        self.scheduler = scheduler()
        # Create the web driver capability
        self.web_manager = WebManager(/ -> self.restart())
    end
    # Start the heating controller
    def start()
        # Indicate the heating controller is starting up
        if util.lcd
            util.lcd.print(1, 'Starting...')
        end
        # Fires when RTC has initialized 
        heating.api.add_rule('Time#Initialized', /  -> self.time_initialized())
        # Fires when MQTT has connected
        if heating.options.use_mqtt
            heating.api.add_rule('Mqtt#Connected', /  -> self.mqtt_connected())
        end
        # Register a button press and power change trigger for each zone
        for i: 1 .. heating.options.zones
            heating.api.add_rule(
                string.format('Button%d#Action', i), / v, t -> self.button_pressed(v, t)
            )
            heating.api.add_rule(
                string.format('POWER%d#State', i), / v, t -> self.power_changed(v, t)
            )
        end
        # If use_cmd option set, register a zone command.
        if heating.options.use_cmd
            heating.api.add_cmd('zone', / c, i, p, j -> self.on_zone_cmd(c, i, p, j))
        end
        # Load the web driver
        tasmota.add_driver(self.web_manager)
    end
    # Restart sequence - do not alter sequence
    def restart()
        self.scheduler.stop()
        util.override.refresh()
        self.scheduler.start()
    end
    # Called once the RTC is initialized (Time#Initialized)
    def time_initialized()
        # Restore override state
        util.override.refresh()
        # Start the scheduler
        self.scheduler.start()
        # If a display is configured, show the time
        if util.lcd
            util.lcd.clear_line(1)
            util.lcd.update_clock()
            var h = / -> util.lcd.update_clock()
            var f = / now -> 60000-now['sec']*1000
            self.ticker = clock()
            self.ticker.start(h, f, 'ticker')
        end
    end
    # When MQTT connects send heating status for all zones
    def mqtt_connected()
        for z: 0 .. util.settings.zones.size()-1
            util.settings.zones.get_status(z).pub_mqtt()
        end
    end
    # Handler for physical buttons
    def button_pressed(v, t)
        var zone = int(t[6])-1
        if v == 'SINGLE'
            self.set_mode(zone, {0:4,4:0})
        elif v == 'DOUBLE'
            self.set_mode(zone, {0:5,5:2,2:3,3:0})
        elif v == 'TRIPLE'
            self.set_mode(zone, {0:1,1:0})
        end
    end
    # Set the mode for a given zone per flow control map
    def set_mode(zone, flow)
        var mode = util.settings.zones.get_mode(zone)
        if !flow.has(mode) return end
        util.override.set(zone, flow[mode])
    end
    # Check webbutton power toggle syncs with heating controller state
    def power_changed(v, t)
        var zone = int(string.split(t, '#')[0][5..])-1
        var mode = util.settings.zones.get_mode(zone)
        self.cmd_set_power(zone, mode, v)
    end
    # Handler for zone command
    # zone1 1 -> turn on heating zone 1
    # zone2 0 -> turn off heating zone 2
    # zone3 {"mode": 5} -> If not in Day mode, switch to Day mode
    # zone3 {"mode": 1, "hours": 2} -> Boost zone 3 for 2 hours
    # The zone will be switched into an appropriate mode
    def on_zone_cmd(cmd, idx, payload, payload_json)
        var zone = idx-1
        if zone < util.settings.zones.size()
            var mode = util.settings.zones.get_mode(zone)
            if isinstance(payload_json, map)
                self.cmd_set_mode(zone, mode, payload_json)
            else 
                self.cmd_set_power(zone, mode, payload)
            end
        end
        var message = string.toupper(string.format('%s%d', cmd, idx))
        heating.api.resp_cmnd(string.format('{"%s": "DONE"}', message))
    end
    # Change the operating mode for the zone if different from current mode
    def cmd_set_mode(zone, mode, payload)
        if !payload.has('mode') return end
        if type(payload['mode']) != 'int' return end
        var to_mode = payload['mode']
        if to_mode < 0 || to_mode > 5 return end
        if to_mode == mode return end
        if to_mode == 1
            if !payload.has('hours') return end
            if type(payload['hours']) != 'int' return end
            var hours = payload['hours']
            if hours  == 1 || hours == 2
                util.override.set(zone, to_mode, hours * 3600)
            end                                   
        else
            util.override.set(zone, to_mode)
        end
    end
    # Change the power state of the zone if different from current state
    def cmd_set_power(zone, mode, payload)
        var from_power = util.settings.zones.get_power(zone, mode)
        var to_power = int(payload)
        # XOR returns true if power needs toggling
        if (to_power == 1 || to_power == 0) && (from_power ? !to_power : to_power)
            # Toggle Advance/Auto
            if mode == 0 || mode == 4
                self.set_mode(zone, {0:4,4:0})
            # Toggle Const On/Off
            elif mode == 2 || mode == 3
                self.set_mode(zone, {2:3,3:2})
            # Toggle Boost or Day 
            elif mode == 1 || mode == 5
                # Switch to Advance mode if Auto doesn't toggle power
                if (util.settings.zones.get_power(zone) ? !to_power : to_power)
                    util.override.set(zone, 0)
                else
                    util.override.set(zone, 4)
                end
            end
        end
    end
end

heating.controller = HeatingController
return heating
