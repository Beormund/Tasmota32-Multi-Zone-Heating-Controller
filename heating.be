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

var heating = module('heating')

# All tasmota calls are accessed via api class
class api
    static wd = tasmota.wd
    static settings = persist    
    static def strftime(format, secs)
        return tasmota.strftime(format, secs)
    end
    static def rtc()
        return tasmota.rtc()
    end
    static def time_dump(secs)
        return tasmota.time_dump(secs)
    end
    static def now()
        var l = tasmota.rtc()['local']
        var t = tasmota.time_dump(l)
        var sfm = t['hour']*3600+t['min']*60+t['sec']
        t.setitem('sfm', sfm)
        t.setitem('local', l)
        return t
    end
    static def tomorrow(day)
        var wd = day != nil ? day : api.now()['weekday']
        return wd < 6 ? wd+1 : 0
    end
    static def cmd(text)
        return tasmota.cmd(text)
    end
    static def log(text)
        tasmota.log(text)
    end
    static def set_timer(millis, func, id)
        tasmota.set_timer(millis, func, id)
    end
    static def remove_timer(id)
        tasmota.remove_timer(id)
    end
    static def set_power(zone, power)
        if api.get_relay_count() > zone
            if tasmota.get_power()[zone] != power
                tasmota.set_power(zone, power)
            end
        end
    end
    static def add_rule(trigger, func)
        tasmota.add_rule(trigger, func)
    end
    static def remove_rule(trigger)
        tasmota.remove_rule(trigger)
    end
    static def add_cmd(cmd, func)
        tasmota.add_cmd(cmd, func)
    end
    static def resp_cmnd(payload)
        tasmota.resp_cmnd(payload)
    end
    static def web_send(msg)
        tasmota.web_send(msg)
    end
    static def response_append(msg)
        tasmota.response_append(msg)
    end
    static def publish_result(payload)
        tasmota.publish_result(payload, '')
    end
    static def get_relay_count()
        def pin(t, enum)
            while gpio.pin(enum, t) != -1 t+=1 end
            return t
        end
        return pin(0, gpio.REL1) + pin(0, gpio.REL1_INV)
    end
end

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
    # --------------------------------------------------------------------------------------------------
    # LCD:  Enable basic support for I2C LCD 20x4/20x2 display (default: false)
    # CMD:  Enable Tasmota/MQTT "zone" command to change a zone's mode (default: true)
    # LED:  Enable addressable LED indicator lights (WS2812 pin needs to be set) (default: false)
    # SYNC: Enable Tasmota UI toggle button names to be kept in sync with zone names (default: false)
    # MQTT: Enable the publishing of MQTT heating zone telemetry (default: true)
    # --------------------------------------------------------------------------------------------------
    static options = {
        'LCD': 1, # 1 << 0
        'CMD': 2, # 1 << 1
        'LED': 4, # 1 << 2
        'SYNC BTNS': 8, # 1 << 3
        'MQTT': 16 # 1 << 4
    }
    # Allowed custom command parameter values
    static cmd_params = {
        'on': true, 
        'off': false, 
        '1': true, 
        '0': false, 
        'true': true, 
        'false': false
    }
    # See screen class for further details. HeatingController initialises the lcd
    static lcd = nil
    # Enable easy access to config. HeatingController initialises the config
    static config = nil
    # Enable access to override capability. HeatingController initialises
    static override = nil
    # Enable access to scheduler capability. HeatingController initialises
    static scheduler = nil
    # Enable access to web manager capability. HeatingController initialises
    static web_manager = nil
    # The buttons class handles button clicks (1 button per heating zone)
    static buttons = nil
    # The relays class handles relay power state changes
    static relays = nil
    # The zone_command class handles custom 'zone' command
    static zone_command = nil
    # Used to create timers for override boost and displaying time
    static def set_timer(f, d, id, r)
        api.set_timer(
            d(api.now()), 
            def() f() if !r return end util.set_timer(f, d, id, r) end, 
            id
        )
    end
    # Used to load HTML for Configure Heating UI
    static def load_file(fn)
        var obj, f
        f = open(api.wd .. fn, 'r')
        obj = json.load(f.read())
        f.close()
        return obj
    end
end

# If options['LCD'] is set this class loads the display.be driver
class screen
    var lcd
    def init()
        self.lcd = display.lcd_i2c()
    end
    def power(bool)
        self.lcd.set_backlight(bool)
    end
    def update_clock()
        var ls = api.rtc()['local']
        self.lcd.write_line(api.strftime('%H:%M %a %d %b %y', ls), 1)
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
    def start_clock()
        self.clear_line(1)
        self.update_clock()
        var h = / -> self.update_clock()
        var f = / now -> 60000-now['sec']*1000
        util.set_timer(h, f, 'ticker', true)
    end
    def stop_clock()
        api.remove_timer('ticker')
    end
end

# A status contains information about the current state of a zone
class status
    var zone, mode, power, expiry, label, key, state
    # @param zone: index of zone from api.settings.zones
    # @param mode: which mode the zone is currently set to
    # @param power: on/off state of zone
    # @param expiry: next on/off time for auto or expiry for boost
    def init(zone, mode, power, expiry)
        self.zone = zone
        self.label = api.settings.zones.get_label(self.zone)
        self.mode = mode
        self.key = util.modes[self.mode]
        self.power = power
        self.state = self.power ? 'On' : 'Off'
        self.expiry = expiry
    end
    # Display max 20 chars: e.g., 'HTG1 off until 16:30'
    def set_lcd()
        if !util.lcd return end
        var fmt = 12&(1<<self.mode) ? "%s %s Const" : '%s %s until %%R'
        var args = [fmt, self.label, self.state]
        util.lcd.print(self.zone+2, self.format(args)) 
    end
    # WS2812 LED (1 pixel per zone) indicator
    def set_led()
        if !util.config.is_option_set(util.options['LED']) return end
        var color = self.power ? util.colors[self.mode] : 'FF0000'
        api.cmd(string.format('Led%d #%s', self.zone+1, color))
    end
    # Publish this status as an MQTT message
    def pub_mqtt()
        if !util.config.is_option_set(util.options['MQTT']) return end
        api.publish_result(json.dump(self.tomap()))
    end
    # Sends as sensor payload to Web manager
    def set_sensor()
        # "{s}ZN1 On until Fri 22:00{m}Auto Mode{e}"
        var fmt = 12&(1<<self.mode)
            ? '{s}<a href="/hm">%s %s</a>{m}Const Mode{e}'
            : '{s}<a href="/hm">%s %s until %%a %%R</a>{m}%s Mode{e}'
        var args = [fmt, self.label, self.state, self.key]
        var msg = self.format(args)
        api.settings.zones[self.zone].sensor = msg
    end
    # Log info with the BRY: prefix
    def log_info()
        api.log('BRY: ' .. self.get_info())
    end
    # E.g., 'HTG1 Auto off until 16:30 Mon 18 Oct 21'
    def get_info()
        var fmt = 12&(1<<self.mode)
            ? '%s %s Const' 
            : '%s %s %s until %%H:%%M %%a %%d %%b %%y'
        var args = [fmt, self.label, self.key, self.state]
        return self.format(args)
    end
    def format(args)
        return api.strftime(
            call(string.format, args), 
            self.expiry
        )
    end
    # Update logs, LED, MQTT and LCD screen
    def notify()
        self.log_info()
        self.set_sensor()
        self.set_led()
        self.pub_mqtt()
        self.set_lcd()
    end
    # Helper map for self.pub_mqtt()
    def tomap()
        return {
            "Zone" .. self.zone+1: {
                "Label": self.label,
                "Mode": self.key,
                "Power": self.state,
                "Until": self.format("%%FT%%T")
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
    var sensor
    def init(o)
        self.sensor = ''
        super(self).init()
        o = isinstance(o, map) ? o : {"l": o ,"e": 0, "m": 0, "p": 0}
        for k: o.keys()
            self[k] = o[k]
        end
    end
    # Returns the zone's mode (current or previous)
    def get_mode(p)
        var lsb = p ? 3 : 0, msb = lsb + 2
        return (self[self.mode] >> lsb) & ~(~0 << (msb-lsb+1))
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
    # Gets a zone by list index or nil
    def get(idx)
        if idx >= 0 && idx < self.size()
            return self[idx]
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
        return self[z].get_mode(p)
    end
    # Set the mode for a given zone
    def set_mode(z, m)
        var current = self.get_mode(z)
        if current != m
            self[z][zone.mode] = current << 3
            self[z][zone.mode] += m
        end
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
    def tojson()
        var l = {}
        for z: self.keys()
            var m = self.get_status(z).tomap()
            var key = 'Zone' .. z+1
            l.setitem(key, m[key])
        end
        return json.dump(l)
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
    # true if index i of list k (days/zones) is set
    def is_set(k, i)
        return !!(self[k] & (1 << i))
    end
    def set_zone(zone)
        self[self.zones] += (1 << zone)
    end
    def remove_zone(zone)
        var mask = -1 << zone
        var x = self[self.zones]
        self[self.zones] = ((x ^ (x >> 1)) & mask) ^ x
    end
    # Converts a string time to seconds from midnight
    # E.g., 10:15 -> 10x3600 + 15x60 
    def str2secs(str)
        var hours = int(str[0..1])
        var mins = int(str[3..4])
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
        var now = api.now()
        var sfm = now['sfm'] # Now as secs from midnight
        var wd = now['weekday'] # Today [0 .. 6]
        var i = t <= sfm ? 1 : 0 # Has on/off time past?
        var day = i ? api.tomorrow(wd) : wd 
        while !self.is_set(self.days, day) i+=1
            day = api.tomorrow(day)            
        end
        return ( i ? 86400*i-(sfm-t) : t-sfm) + now['local']
    end
    # Calculates if the current schedule is on or off
    def is_running(zone)
        var n = api.now()
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
        for s: self.keys()
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
    # Set a zone for each schedule
    def set_zone(zone)
        for s: self s.set_zone(zone) end
    end
    # Unset a zone for each schedule
    def remove_zone(zone)
        for s: self s.remove_zone(zone) end
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
        return self.get_first_on(zone, api.tomorrow(day))
    end
    # Retrieves the first on or last off schedule for day
    def get_day_onoff(zone, f, day)
        if self.size() == 0 return end
        var wd = day != nil ? day : api.now()['weekday']
        var l = 0, t = nil
        while (l < 7 && !t) l+=1 
            for s: self
                if s.is_set(s.zones, zone) && s.is_set(s.days, wd)
                    t = !t ? s : t
                    t = f(s,t) ? s : t
                end
            end
            wd = api.tomorrow(wd)
        end
        return t
    end
    # Gets the next free id for new schedules
    def next_id()
        return self.size()+1
    end
    # Used to reset all schedule ids when list changes
    def reindex()
        for i: self.keys()
            self[i][schedule.id] = i+1
        end
    end
end

# Configures zones, schedules and labels
class config
    def get_next_status(zone)
        if api.settings.zones.get_mode(zone)
            # Return a zone status if mode is in override
            return api.settings.zones.get_status(zone)
        else
            # Return a schedule status if mode is auto
            return api.settings.schedules.get_next_status(zone)
        end
    end
    # If sync_webbuttons is true set the relay toggle button to label
    def set_webbutton(btn, label)
        # Don't set the quasi Light/WS2812 button; only relays...
        if btn > api.get_relay_count() return end 
        api.cmd(string.format('webbutton%d %s', btn, label))
    end
    def set_webbuttons()
        for z: api.settings.zones.keys()
            self.set_webbutton(z+1, api.settings.zones.get_label(z))
        end
    end
    # Returns true if option set (use static option enumeration)
    # E.g., is_option_set(option.MQTT)
    def is_option_set(opt) 
        return !!(api.settings.options & opt)
    end
    # Enable/disable an option
    # E.g., set_option(options.MQTT, true)
    def set_option(opt, set)
        api.settings.options ^= (-int(set) ^ api.settings.options) & opt
    end
    # If LCD option is set, enable the screen
    def enable_display()
        if !util.lcd 
            util.lcd = screen()
            util.lcd.start_clock()
            # Update zone info
            for z: api.settings.zones.keys()
                var stat = api.settings.zones.get_status(z)
                stat.set_lcd()
            end
        end
    end    
    # If LCD option is unset, disable the screen
    def disable_display()
        if util.lcd
            util.lcd.stop_clock()
            util.lcd.clear_screen()            
            util.lcd = nil
        end
    end
    # Saves the configuration to _persist.json
    def save()
        api.settings.save()
    end
    # Loads zones and schedules from _persist.json
    # If _persist.json does not contain the data default
    # options, zones, and schedules are created.
    def load()
        if !api.settings.has('options')
            api.settings.options = 16 # CMD enabled
        end
        if api.settings.has('zones')
            # Need to convert from a list to zones sub-class
            api.settings.zones = zones(api.settings.zones)
        else
            api.settings.zones = zones()
            for i: 1 .. api.get_relay_count()
                api.settings.zones.push(zone('ZN' .. i))
            end
        end
        if api.settings.has('schedules')
            # Need to convert from a list to schedules sub-class
            api.settings.schedules = schedules(api.settings.schedules)
        else
            var sum = (1 << api.settings.zones.size())-1
            # Four initial schedules are created AM & PM for weekdays & w/e
            # 62 = Mon-Fr; 65 = Sat/Sun
            api.settings.schedules = schedules([
                {"i": 1, "1": 23400, "0": 30600, "d": 62, "z": sum},
                {"i": 2, "1": 59400, "0": 79200, "d": 62, "z": sum},
                {"i": 3, "1": 27000, "0": 37800, "d": 65, "z": sum},
                {"i": 4, "1": 61200, "0": 82800, "d": 65, "z": sum}
            ])
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
        for s: api.settings.schedules
            self.set_timer(s)
        end
        self.on_start()
    end
    def stop()
        self.running = false
        api.remove_timer('schedule')
    end
    def set_timer(s)
        # Get the time now in seconds
        var now = api.rtc()['local']
        # Is the schedule switching on or off?
        var power = s.is_running()
        # Get the next run time depending on power state
        var runat = s.get_runat(power ? s.off : s.on)
        # Timers are set in millis (add 1 second safety margin)
        var millis = (runat+1 - now) * 1000
        # Call on_pop when the timer expires
        api.set_timer(millis, / -> self.on_pop(s), 'schedule')
    end
    # This method is only used when the scheduler is first run.
    # It retrieves statuses for next auto mode run times
    def on_start()
        self.running = true
        for z: api.settings.zones.keys()
            if api.settings.zones.get_mode(z)
                # If mode is override set schedule power state
                var power = api.settings.schedules.get_next_status(z).power
                api.settings.zones.set_power(z, power)
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
        for zone: api.settings.zones.keys()
            # Is the zone set for this schedule?
            if !s.is_set(s.zones, zone) continue end
            # What mode is the zone in?
            var mode = api.settings.zones.get_mode(zone)
            if mode == 0 # Auto
                self.on_completed(zone)
            elif mode == 4 # Advance
                # If previous mode was Day switch back to Day mode, else Auto
                var previous = api.settings.zones.get_mode(zone, true) == 5 ? 5 : 0
                # Update zone configuration state
                api.settings.zones.set_zone(zone, previous, power)
                self.on_completed(zone)
            elif mode == 5 # Daytime
                # If schedule matches first on/last off, update power, expriry etc
                if util.override.check_day(zone, s, power) 
                    self.on_completed(zone)
                end
                # Update schedule power
                api.settings.zones.set_power(zone, power)
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
        api.settings.zones.set_zone(zone, stat.mode, stat.power, stat.expiry)
        # Set the power state of the relay
        api.set_power(zone, stat.power)
        # Update logs, LED, MQTT and LCD screen
        stat.notify()
    end
end

# This class handles the manual override of scheduling
class override
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
        var current = api.settings.zones.get_mode(zone)
        if mode != current && current == 1
            self.on_boost_cancel(zone)
        end
    end
    # Set the relay power state and log/display message for zone
    def on_completed(zone)
        var stat = api.settings.zones.get_status(zone)
        api.set_power(zone, stat.power)
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
        util.set_timer(h, f, id, false)
        var expiry = (!secs ? 3600 : secs) + api.rtc()['local']
        api.settings.zones.set_zone(zone, 1, true, expiry)
    end
    # Called by boost handler when timer completes
    def on_boost_end(zone)
        # Set to previous mode. check_boost() will cancel boost
        self.set(zone, api.settings.zones.get_mode(zone, true))
    end
    # Called when boost timer is active but mode is changed
    def on_boost_cancel(zone)
        var id = 'boost' .. zone
        api.remove_timer(id)
        api.settings.zones.set_power(zone, false, true)
        api.settings.zones.set_expiry(zone, 0)
        api.log(string.format(
            'BRY: %s boost off', 
            api.settings.zones.get_label(zone))
        )
    end
    # Toggle zone state
    def advance(zone)
        var stat = api.settings.schedules.get_next_status(zone)
        api.settings.zones.set_zone(zone, 4, !stat.power, stat.expiry)
    end
    # Swtich zone to timer mode
    def auto(zone)
        var stat = api.settings.schedules.get_next_status(zone)
        api.settings.zones.set_zone(zone, 0, stat.power, stat.expiry)
    end
    # Switch zone permanently on
    def on(zone)
        api.settings.zones.set_zone(zone, 2, true)
    end
    # Switch zone permanently off
    def off(zone)
        api.settings.zones.set_zone(zone, 3, false)
    end
    # Switch zone on from first 'ON' time until last 'OFF' time 
    def day(zone, _dt)
        var dt = _dt ? _dt : api.settings.schedules.get_daytime(zone)
        var start = dt['start'], finish = dt['finish']
        if !start || !finish 
            self.set(zone, 0)
            return
        end
        var n = api.now()
        var on = start.get_runat(start.on)
        var off = finish.get_runat(finish.off)
        var power = (on > off || on <= n['local']) && n['local'] <= off
        var expiry
        if power expiry = off
        elif n['sfm'] < start[start.on] expiry = on
        elif n['sfm'] > finish[finish.off]
            var nfo = api.settings.schedules.get_next_first_on(zone, n['weekday'])
            expiry = nfo.get_runat(nfo.on)
        end
        api.settings.zones.set_zone(zone, 5, power, expiry)
    end
    # Used by scheduler to test if schedule matches day first on or last off time
    def check_day(zone, s, power)
        var dt = api.settings.schedules.get_daytime(zone)
        var start = dt['start'], finish = dt['finish']
        if power ? start[start.id] == s[s.id] : finish[finish.id] == s[s.id]
            self.day(zone, dt)
            return true
        end
    end
    # Refresh overrides for all zones on re-start or schedule/zone changes.
    def refresh()
        for zone: api.settings.zones.keys()
            var mode = api.settings.zones.get_mode(zone)
            if mode == 1
                var expiry = api.settings.zones.get_expiry(zone) - api.rtc()['local']
                self.set(zone, mode, expiry)
            elif mode  > 1
                self.set(zone, mode)
            end
        end
    end
    # Set the mode for a given zone per flow control map
    def toggle_mode(zone, flow)
        var mode = api.settings.zones.get_mode(zone)
        if !flow.has(mode) return end
        self.set(zone, flow[mode])
    end
end

# Display Schedule Summary/Editor in 'Configure Heating'
class ScheduleGUI
    # Get list of day indices
    # bits 30 -> [-MTWT--]
    def bits2days(bits)
        var l = []
        for d: util.days.keys()
            bits & (1 << d) 
            ? l.push(util.days[d][0]) 
            : l.push("<mark>" .. util.days[d][0] .. "</mark>")
        end
        return l.concat()
    end
    # Send a list of schedules as HTML fragment
    def show_schedules(html)
        webserver.content_send(html[0])
        for s: api.settings.schedules
            var day_str = self.bits2days(s[s.days])
            var zone_str = ''
            for z: api.settings.zones.keys()
                if !s.is_set(s.zones, z) continue end
                zone_str += api.settings.zones.get_label(z)
                if z < api.settings.zones.size()-1
                    zone_str += ' '
                end
            end
            var t = size(zone_str) > 10
            webserver.content_send(
                string.format(
                    html[1], s[s.id], s[s.id], s.secs2str(s[s.on]), 
                    s.secs2str(s[s.off]), day_str, zone_str, 
                    t ? zone_str[0 .. 11] + ".." : zone_str
                )
            )
        end
        var new_id = api.settings.schedules.next_id()
        webserver.content_send(string.format(html[2], new_id ))
    end
    # Displays a web control for editing a single schedule
    def show_editor(id, html)
        var s = api.settings.schedules.get(id)
        var action = s ? 'update' : 'new'
        s = s ? s : schedule()
        webserver.content_send(string.format(html[0], id, id, s.secs2str(s[s.on]), s.secs2str(s[s.off])))
        for d: util.days.keys()
            var checked = s.is_set(s.days, d) ? 'checked' : ''
            var dl = util.days[d]
            webserver.content_send(string.format(html[1], dl, 1 << d, checked, dl, dl))
        end
        webserver.content_send(html[2])
        for z: api.settings.zones.keys()
            var checked = s.is_set(s.zones, z) ? 'checked' : '', zl = api.settings.zones.get_label(z)
            webserver.content_send(string.format(html[3], zl, 1 << z, checked, zl, zl))
        end
        webserver.content_send(string.format(html[4], action, id))
        if action == 'update'
            webserver.content_send(html[5])
        end
        webserver.content_send(html[6])
    end
end

# Displays zone sumarry/editor widgets in 'Configure Heating'
class ZoneGUI
    # Shows a list of zones with status info
    def show_zones(html)
        webserver.content_send(html[0])
        for z: 1 .. api.settings.zones.size()
            var info = api.settings.zones.get_status(z-1).get_info()
            webserver.content_send(
                string.format(html[1], z, z, info)
            )
        end
        var new_id = api.settings.zones.size()+1
        webserver.content_send(string.format(html[2], new_id ))
        webserver.content_send(html[3])
    end
    # Displays a web control for editing a single zone
    def show_editor(zid, html)
        var z = api.settings.zones.get(zid-1)
        var action = z != nil ? 'update' : 'new'
        z = z ? z : zone('ZN' .. zid)
        webserver.content_send(string.format(html[0], zid-1, zid, z[zone.label]))
        for k: util.modes.keys()
            var checked = z.get_mode() == k ? 'checked' : ''
            var mode = util.modes[k]
            webserver.content_send(string.format(html[1], mode, k, checked, mode, mode))
        end
        webserver.content_send(html[2])
        webserver.content_send(string.format(html[3], action))
        if action == 'update'
            webserver.content_send(html[4])
        end
        webserver.content_send(html[5])
    end
end

# Displays options in 'Configure Heating'
class OptionsUI
    def show_options(html)
        webserver.content_send(html[0])
        for k: util.options.keys()
            var checked = util.config.is_option_set(util.options[k]) ? 'checked' : ''
            webserver.content_send(string.format(html[1], k, checked, k, k))
        end
        webserver.content_send(html[2])
    end
end

# HTTP driver for "Configure Heating" page
class WebManager : Driver
    var controller, restart, html, button
    def init(restart)
        self.restart = restart
        self.html = util.load_file('html.json')
        self.button = self.html['button']
        self.html = nil
    end
    # Displays a "Configure Heating" button on the configuration page
    def web_add_config_button()
        webserver.content_send(self.button)
    end
    def web_sensor()
        var msg = ''
        for z: api.settings.zones
            msg+= z.sensor
        end
        api.web_send(msg)
    end
    def json_append()
        var jsonstr = api.settings.zones.tojson()
        var msg = ",\"Heating\":" .. jsonstr
        api.response_append(msg)
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
    def update_zone(id)
        def set_mode(id, mode)
            if mode == 1
                if webserver.has_arg('hours[]')
                    var hours = int(webserver.arg('hours[]'))
                    util.override.set(id, mode, hours * 3600)
                end
            else
                util.override.set(id, mode)
            end
        end
        if webserver.has_arg('delete')
            # Check boost.If active cancel...
            if api.settings.zones.get_mode(id) == 1
                util.override.on_boost_cancel(id)
            end
            # Remove last button and relay triggers
            util.buttons.pop_trigger()
            util.relays.pop_trigger()
            # Remove zone from zone collection
            api.settings.zones.pop(id)
            # Remove zone from schedules
            api.settings.schedules.remove_zone(id)
            # Clear display zone info
            if util.lcd
                for l: 2 .. api.settings.zones.size()+2
                    util.lcd.clear_line(l)
                end
            end
            # Re-sync power state for reshuffled zones
            for z: api.settings.zones.keys()
                var stat = api.settings.zones.get_status(z)
                # Set the power state of the relay
                api.set_power(z, stat.power)
                # Notify display etc.
                stat.notify()
            end
            # Sync the Tasmota UI Toggle buttons
            if util.config.is_option_set(util.options['SYNC BTNS'])
                util.config.set_webbuttons()
            end
            return
        end
        if webserver.has_arg('new')
            # Process label
            var label = webserver.has_arg('label') ? webserver.arg('label') : ''
            label = size(label) ? label : 'ZN' .. id+1
            # Add the new zone to the zones collection
            api.settings.zones.push(zone(label))
            # Add the new zone to schedules
            api.settings.schedules.set_zone(id)
            # Sync button and relay triggers
            util.buttons.add_trigger(id)
            util.relays.add_trigger(id)
            # Sync the Tasmota UI Toggle buttons
            if util.config.is_option_set(util.options['SYNC BTNS'])
                util.config.set_webbutton(id+1, label)
            end
            # Process mode
            if webserver.has_arg('modes[]')
                var mode = int(webserver.arg('modes[]'))
                set_mode(id, mode)
            end
        elif webserver.has_arg('update')
            # Process label
            var _dirty = false
            if webserver.has_arg('label')
                var label = webserver.arg('label')
                # Only update the label if it has changed
                if size(label) > 0 && label != api.settings.zones.get_label(id)
                    api.settings.zones.set_label(id, label)
                    _dirty = true
                     # Sync the Tasmota UI Toggle buttons
                    if util.config.is_option_set(util.options['SYNC BTNS'])
                        util.config.set_webbutton(id+1, label)
                    end
                end
            end
            # Process mode
            if webserver.has_arg('modes[]')
                var mode = int(webserver.arg('modes[]'))
                # Only update the mode if it has changed
                if mode != api.settings.zones.get_mode(id)
                    set_mode(id, mode)
                    _dirty = false
                end
            end
            # There are updates so update the display and pub to MQTT
            if _dirty
                var stat = api.settings.zones.get_status(id)
                stat.set_lcd()
                stat.pub_mqtt()
                stat.set_sensor()
            end
        end
    end
    # Deletes/Updates/Creates a schedule based on web form entry
    def update_schedule(id)
        if webserver.has_arg('delete')
            api.settings.schedules.pop(id)
            return true
        elif webserver.has_arg('update')
            var schedule = schedule()
            self.fill_schedule(id, schedule)
            return api.settings.schedules.update(schedule)
        elif webserver.has_arg('new')
            var schedule = schedule()
            self.fill_schedule(id, schedule)
            api.settings.schedules.push(schedule)
            return true
        end
    end
    # Updates options
    def update_options()
        for k: util.options.keys()
            var current = util.config.is_option_set(util.options[k])
            var new = webserver.has_arg(k)
            if current != new
                util.config.set_option(util.options[k], new)
                if k == 'LCD'
                    new ? util.config.enable_display() : util.config.disable_display()
                end
            end
        end
    end
    # This HTTP GET manager controls which web controls are displayed
    def page_heating_mgr()
        if !webserver.check_privileged_access() return nil end
        if !self.html self.html = util.load_file('html.json') end
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
            OptionsUI().show_options(self.html['options'])
        end
        webserver.content_button(webserver.BUTTON_CONFIGURATION)
        webserver.content_stop()
        self.html = nil
    end
    # This HTTP POST manager handles the submitted web form data
    def page_heating_ctl()
        if webserver.has_arg('z')
            self.update_zone(int(webserver.arg('z')))
        elif webserver.has_arg('s') 
            if self.update_schedule(int(webserver.arg('s')))
                var rc = self.restart
                rc()
            end
        elif webserver.has_arg('o')
            self.update_options()
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

class component
    def init()
        self.add_triggers()
    end
    def add_trigger(zone)
        api.add_rule(
            string.format(self.fmt(), zone+1), / v, t -> self.on_changed(v, t)
        )
    end
    def add_triggers()
        for i: api.settings.zones.keys()
            self.add_trigger(i)
        end
    end
    def pop_trigger()
        api.remove_rule(
            string.format(self.fmt(), api.settings.zones.size())
        )
    end
end

class buttons: component
    def init(comp) super(self).init() end
    def fmt() return 'Button%d#Action' end
    # Handler for physical buttons
    def on_changed(v, t)
        var zone = int(t[6])-1
        if v == 'SINGLE'
            util.override.toggle_mode(zone, {0:4,4:0})
        elif v == 'DOUBLE'
            util.override.toggle_mode(zone, {0:5,5:2,2:3,3:0})
        elif v == 'TRIPLE'
            util.override.toggle_mode(zone, {0:1,1:0})
        end
    end
end

class relays: component
    def init() super(self).init() end
    def fmt() return 'POWER%d#State' end
    # Check webbutton power toggle syncs with heating controller state
    def on_changed(v, t)
        var zone = int(string.split(t, '#')[0][5..])-1
        var mode = api.settings.zones.get_mode(zone)
        self.cmd_set_power(zone, mode, v)
    end
    # Change the power state of the zone if different from current state
    def cmd_set_power(zone, mode, payload)
        var from_power = api.settings.zones.get_power(zone, mode)
        var to_power = int(payload)
        # XOR returns true if power needs toggling
        if (to_power == 1 || to_power == 0) && (from_power ? !to_power : to_power)
            # Toggle Advance/Auto
            if mode == 0 || mode == 4
                util.override.toggle_mode(zone, {0:4,4:0})
            # Toggle Const On/Off
            elif mode == 2 || mode == 3
                util.override.toggle_mode(zone, {2:3,3:2})
            # Toggle Boost or Day 
            elif mode == 1 || mode == 5
                # Switch to Advance mode if Auto doesn't toggle power
                if (int(api.settings.zones.get_power(zone)) ^ to_power)
                    util.override.set(zone, 4)
                else
                    util.override.set(zone, 0)
                end
            end
        end
    end
end

class zone_command
    def init()
        self.add_command('zone')
    end
    def add_command(cmd)
        api.add_cmd(cmd, / c, i, p, j -> self.on_cmd(c, i, p, j))
    end
    # Handler for zone command
    # zone1 1 -> turn on heating zone 1
    # zone2 0 -> turn off heating zone 2
    # zone3 {"mode": 5} -> If not in Day mode, switch to Day mode
    # zone3 {"mode": 1, "hours": 2} -> Boost zone 3 for 2 hours
    # The zone will be switched into an appropriate mode
    def on_cmd(cmd, idx, payload, payload_json)
        if !util.config.is_option_set(util.options['CMD']) 
            api.resp_cmnd('{"Command": "Unknown"}')
            return
        end
        var zone = idx-1
        if zone < api.settings.zones.size()
            var mode = api.settings.zones.get_mode(zone)
            if isinstance(payload_json, map)
                self.cmd_set_mode(zone, mode, payload_json)
            elif payload == ''
                api.settings.zones.get_status(zone).pub_mqtt()             
            else
                var power = util.cmd_params.find(string.tolower(payload))
                if power != nil 
                    self.cmd_set_power(zone, mode, power) 
                end
            end
        end
        var message = string.toupper(string.format('%s%d', cmd, idx))
        api.resp_cmnd(string.format('{"%s": "DONE"}', message))
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
    def cmd_set_power(zone, mode, to_power)
        var from_power = api.settings.zones.get_power(zone, mode)
        # XOR returns true if power needs toggling
        if from_power ? !to_power : to_power
            # Toggle Advance/Auto
            if mode == 0 || mode == 4
                util.override.toggle_mode(zone, {0:4,4:0})
            # Toggle Const On/Off
            elif mode == 2 || mode == 3
                util.override.toggle_mode(zone, {2:3,3:2})
            # Toggle Boost or Day 
            elif mode == 1 || mode == 5
                # Switch to Advance mode if Auto doesn't toggle power
                if api.settings.zones.get_power(zone) ? !to_power : to_power
                    util.override.set(zone, 4)
                else
                    util.override.set(zone, 0)
                end
            end
        end
    end
end

# The main class for setting up the heating controller
class HeatingController
    def init()
        # Create the configuration capability
        util.config = config()
        # Load persisted label, zone and schedule data
        util.config.load()
        # If sync_webbuttons is set, update relay toggle buttons
        if util.config.is_option_set(util.options['SYNC BTNS'])
            util.config.set_webbuttons()
        end
        # If use_lcd is set, create a minute ticker to display the time
        if util.config.is_option_set(util.options['LCD'])
            util.lcd = screen() 
        end
        # Create the override capability
        util.override = override()
        # Create the scheduler capability
        util.scheduler = scheduler()
        # Create the web driver capability
        util.web_manager = WebManager(/ -> self.restart())
    end
    # Start the heating controller
    def start()
        # Indicate the heating controller is starting up
        if util.lcd
            util.lcd.print(1, 'Starting...')
        end
        # Fires when RTC has initialized 
        api.add_rule('Time#Initialized', /  -> self.time_initialized())
        # Fires when MQTT has connected
        api.add_rule('Mqtt#Connected', /  -> self.mqtt_connected())
        # Register button press triggers
        util.buttons = buttons()
        # Register power state change triggers
        util.relays = relays()
        # Register zone command.
        util.zone_command = zone_command()
        # Load the web driver
        tasmota.add_driver(util.web_manager)
    end
    # Restart sequence - do not alter sequence
    def restart()
        util.scheduler.stop()
        util.override.refresh()
        util.scheduler.start()
    end
    # Called once the RTC is initialized (Time#Initialized)
    def time_initialized()
        # Restore override state
        util.override.refresh()
        # Start the scheduler
        util.scheduler.start()
        # If a display is configured, show the time
        if util.lcd
            util.lcd.start_clock()
        end
    end
    # When MQTT connects send heating status for all zones
    def mqtt_connected()
        if util.config.is_option_set(util.options['MQTT'])
            for z: api.settings.zones.keys()
                api.settings.zones.get_status(z).pub_mqtt()
            end
        end
    end    
end

heating.controller = HeatingController
return heating
