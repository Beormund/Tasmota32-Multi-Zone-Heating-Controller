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
    static WS2812 = gpio.pin(gpio.WS2812, 1) 
    static def strftime(format, secs)
        return tasmota.strftime(format, secs)
    end
    static def strptime(time, format)
        return tasmota.strptime(time, format)
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
    static def add_driver(inst)
        tasmota.add_driver(inst)
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

# Enables consumers to subscribe to wifi status changes
class wifi
   # Is wifi connected? Used by displays
   static connected
   # Used to hold wifi notification callbacks
   static callbacks
   # Next set of functions help notify consumers of wifi status changes
   static def set_status(bool)
       wifi.connected = bool
       wifi.notify()
   end
   # Notify all callbacks of change of wifi status
   static def notify()
       if !wifi.callbacks return end
       var i = 0
       while i < size(wifi.callbacks)
           wifi.callbacks[i].cb(wifi.connected)
           i += 1
       end
   end
   # Add wifi callbacks
   static def add_cb(cb, id)
       class wc
           var cb, id
           def init(cb, id)
               self.cb = cb
               self.id = id
           end
       end
       if !wifi.callbacks
           wifi.callbacks = []
       end
       wifi.callbacks.push(wc(cb, id))
   end
   # Remove wifi callbacks
   static def remove_cb(id)
       if !wifi.callbacks return end
       var i = 0
       while i < size(wifi.callbacks)
           if wifi.callbacks[i].id == id
               wifi.callbacks.remove(i) 
           else
               i += 1
           end
       end
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
        0x00FF00, # Green
        0x800080, # Purple
        0x088F8F, # Dark Cyan
        0xFF00FF, # Magenta
        0x0000FF, # Blue
        0xf58231  # Yellow
    ]
    # --------------------------------------------------------------------------------------------------
    # DISPLAY:  Enable support for I2C LCD 20x4/20x2 display or SPI 320x240 ILI9341 (default: false)
    # CMD:  Enable Tasmota/MQTT "zone" command to change a zone's mode (default: true)
    # LED:  Enable addressable LED indicator lights (WS2812 pin needs to be set) (default: true)
    # SYNC: Enable Tasmota UI toggle button names to be kept in sync with zone names (default: false)
    # MQTT: Enable the publishing of MQTT heating zone telemetry (default: true)
    # --------------------------------------------------------------------------------------------------
    static options = {
        'DISPLAY': 1, # 1 << 0
        'UI': 2, # 1 << 1
        'LED': 4, # 1 << 2
        'SYNC': 8, # 1 << 3
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
    # See screen modules for further details. HeatingController initialises the screen
    static scr = nil
    # Enabled access to WS2812 LEDs
    static WS2812 = nil
    # Enable easy access to config. HeatingController initialises the config
    static config = nil
    # Enable access to override capability. HeatingController initialises
    static override = nil
    # Enable access to scheduler capability. HeatingController initialises
    static scheduler = nil
    # Enable access to tasmota driver capability. HeatingController initialises
    static driver = nil
    # The buttons class handles button clicks (1 button per heating zone)
    static buttons = nil
    # The relays class handles relay power state changes
    static relays = nil
    # Calls a function passing in a time formatter
    static def set_time(callback)
        var t = api.now()['local']
        callback(/fmt-> api.strftime(fmt, t), t)
    end
    # Used to create timers for override boost and displaying time
    static def set_timer(millis, callback, id, repeat)
        var now = api.now()
        api.set_timer(
            millis(now),
            def()
                util.set_time(callback)
                if !repeat return end
                util.set_timer(millis, callback, id, repeat)
            end,
            id
        )
    end
    static def remove_timer(id)
        api.remove_timer(id)
    end
    # find a key in map, case insensitive, return actual key or nil if not found
    static def find_key_i(m, keyi)
        var keyu = string.toupper(keyi)
        if isinstance(m, map)
            for k:m.keys()
                if string.toupper(k)==keyu
                    return k
                end
            end
        end
    end
    # Restarts the scheduler (i.e., when schedules are updated)
    static def restart()
        # Restart sequence - do not alter sequence
        util.scheduler.stop()
        util.override.refresh()
        util.scheduler.start()
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
    def set_screen()
        if !util.scr return end
        util.scr.update_zone(self)
    end
    # WS2812 LED (1 pixel per zone) indicator
    def set_led()
        if !util.config.is_option_set(util.options['LED']) return end
        var color = self.power ? util.colors[self.mode] : 0xFF0000
        util.WS2812.set_pixel_color(self.zone, color)
        util.WS2812.show()
    end
    # Publish this status as an MQTT message
    def pub_mqtt()
        if !util.config.is_option_set(util.options['MQTT']) return end
        api.publish_result(json.dump(self.tojson()))
    end
    # Sends as sensor payload to Web manager
    def set_sensor()
        # "{s}ZN1 On until Fri 22:00{m}Auto Mode{e}"
        var linkstart = '', linkend = ''
        if util.config.is_option_set(util.options['UI'])
            linkstart = '<a href="/hm">'
            linkend = '</a>'
        end
        var fmt = 12&(1<<self.mode)
            ? '{s}%s%s %s%s{m}Const Mode{e}'
            : '{s}%s%s %s until %%a %%R%s{m}%s Mode{e}'
        var args = [fmt, linkstart, self.label, self.state, linkend, self.key]
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
            ? '%s Const %s' 
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
    # Update logs, LED, MQTT and screen
    def notify()
        self.log_info()
        self.set_sensor()
        self.set_led()
        self.pub_mqtt()
        self.set_screen()
    end
    # Helper map for self.pub_mqtt()
    def tojson()
        var zjs = api.settings.zones[self.zone].tojson()
        zjs['id'] = self.zone+1
        return {"Zone":  zjs}
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
        o = isinstance(o, map) ? o : {"l": o?o:'' ,"e": 0, "m": 0, "p": 0}
        for k: o.keys()
            self[k] = o[k]
        end
    end
    # validates json payload values if keys present:
    # {"label": "Zone 1", "mode": 0} or {"label": "Zone 1", "mode": 1, "hours": 2}
    # If validation successful returns a zone instance else raises an assert_failed error 
    static def fromjson(m)
        var zone = zone()
        var msg = / s -> string.format("Error: %s invalid or missing", s)
        for k: m.keys()
            var key = string.tolower(k)
            if key == 'label'
                assert(type(m[k]) == 'string', msg(k))
                zone[zone.label] = m[k]
            elif key == 'mode'
                assert(type(m[k]) == 'int', msg(k))
                assert(m[k] >=0 && m[k] < size(util.modes), msg(k)) 
                zone[zone.mode] = m[k]
            elif key == 'hours'
                assert(type(m[k]) == "int", msg(k))
                assert(m[k] == 1 || m[k] == 2, msg(k))
                # hours is not a member of zone so convert to expiry
                zone[zone.expiry] = m[k] * 3600
            end
        end
        if zone.contains(zone.mode) && zone[zone.mode] == 1
            # If mode is boost then expiry should be > 0
            assert(zone[zone.expiry] > 0, msg('hours'))
        end
        return zone
    end
    # Returns the zone's mode (current or previous)
    def get_mode(p)
        var lsb = p ? 3 : 0, msb = lsb + 2
        return (self[self.mode] >> lsb) & ~(~0 << (msb-lsb+1))
    end
    # Returns the zone's power state. Mode is optional 
    def get_power(m)
        return !!((self[self.power] >> int(!m)) & 1)
    end
    def tojson()
        return {
            "label": self[self.label],
            "mode": util.modes[self.get_mode()],
            "power": self.get_power(self.get_mode()) ? "On" : "Off",
            "until": 12&(1<<self.get_mode()) 
                ? nil 
                : api.strftime("%FT%T", self[self.expiry]),
            "expiry": self[self.expiry]
        }
    end
end

# A collection of zones
class zones: list
    def init(l)
        super(self).init()
        if isinstance(l, list)
            var z = 0
            while z < size(l)
                self.push(zone(l[z]))
                z += 1
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
        return self[z].get_power(m)
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
        var l = []
        for k: self.keys()
            var jsz = self[k].tojson()
            jsz['id'] = k+1
            l.push(jsz)
        end
        return l
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
    # validates if a json payload is in the following format:
    # {"on": "07:00", "off": "12:59", "id":3, "days": [0,1,1,1,1,1,0], "zones":[1,1,0]}
    # If validation successful returns a schedule instance else raises an assert_failed error 
    static def fromjson(m)
        var sched = schedule()
        var msg = / s -> string.format("Error: %s missing or invalid", s)
        for k:  ["on", "off", "id", "days", "zones"]
            var key = util.find_key_i(m, k)
            assert(key, msg(k))
            if k == 'on' || k == 'off'
                var t = api.strptime(m[key], '%H:%M')
                assert(t && t['hour']<24 && t['min']<60, msg(k))
                sched[k == 'on' ? schedule.on : schedule.off] = t['hour']*3600+t['min']*60
            elif k == 'id'
                assert(type(m[key]) == 'int', msg(k))
                sched[schedule.id] = m[key]
            elif k == 'days' || k == 'zones'
                assert(classname(m[key]) == 'list', msg(k))
                var l = k == 'days' ? 7 : api.settings.zones.size()
                assert(size(m[key]) == l, msg(k))
                var x = 0
                for lk: m[key].keys()
                    var v = m[key][lk]
                    assert(v == 0 || v == 1, msg(k))
                    if v x+= (1 << lk) end
                end
                sched[k == 'days' ? schedule.days : schedule.zones] = x
            end
        end
        assert(sched[schedule.off] > sched[schedule.on], msg("on/off times"))
        return sched
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
    # Gets the schedule's days as a list [0,1,1,1,1,1,0]
    def days2list()
        var l = []
        var d = 0
        while d < size(util.days)
            l.push(int(self.is_set(self.days, d)))
            d += 1
        end
        return l
    end
    # Gets the schedule's zones as a list [1,1,0]
    def zones2list()
        var l = []
        var z = 0
        while z <  size(api.settings.zones)
            l.push(int(self.is_set(self.zones, z)))
            z += 1
        end
        return l
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
        while !self.is_set(self.days, day) 
            i += 1
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
    def tojson()
        return {
            "on": self.secs2str(self[self.on]),
            "off": self.secs2str(self[self.off]),
            "id": self[self.id],
            "days": self.days2list(),
            "zones": self.zones2list()
        }
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
        return true
    end
    # list.pop overridden to remove schedule by id
    def pop(id)
        var _dirty = false
        for s: self.keys()
            if self[s][schedule.id] == id
               super(self).pop(s)
               _dirty = true
               break 
            end
        end
        if _dirty
            self.reindex()
        end
        return _dirty
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
        if current
            if current == updated
                return false
            else 
                for k: current.keys()
                     current[k] = updated[k]
                end
                return true
            end
        else 
            return false
        end
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
    def tojson()
        var l = []
        for k: self
            l.push(k.tojson())
        end
        return l
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
    # Returns true if option set (use static option enumeration)
    # E.g., is_option_set(util.option['MQTT'])
    def is_option_set(opt) 
        return !!(api.settings.options & opt)
    end
    # Enable/disable an option
    # E.g., set_option(util.options['MQTT'], true)
    def set_option(opt, set)
        api.settings.options ^= (-int(set) ^ api.settings.options) & opt
        self.configure_option(opt, set, true)
    end
    def configure_option(opt, set, configure)
        if opt == util.options['DISPLAY']
            set ? self.enable_display(configure) : self.disable_display()
        elif opt == util.options['LED']
            set ? self.enable_leds(configure) : self.disable_leds()
        elif opt == util.options['SYNC'] && set
            self.set_webbuttons()
        elif opt == util.options['UI']
            set ? self.enable_ui() : self.disable_ui()
        end
    end
    # Configures options - called by HeatingController on startup
    def configure_options()
        for opt: util.options
            self.configure_option(opt, self.is_option_set(opt))
        end
    end
    # If UI option is set, enable the Tasmota UI
    # Obviously if the UI is disabled from the UI it can
    # only be re-enabled via the HeatingOptions command
    def enable_ui()
        import sys
        var path = sys.path()
        path.push(api.wd)
        import heating_ui
        heating_ui.wd = api.wd
        heating_ui.start()
        path.pop()
        for z: api.settings.zones.keys()
            var stat = api.settings.zones.get_status(z)
            stat.set_sensor()
        end
    end
    def disable_ui()
        import sys
        var path = sys.path()
        path.push(api.wd)
        import heating_ui
        heating_ui.stop()
        path.pop()
        for z: api.settings.zones.keys()
            var stat = api.settings.zones.get_status(z)
            stat.set_sensor()
        end
    end
    # If DISPLAY option is set, enable the screen
    def enable_display(configure)
        if !util.scr
            import introspect, global, sys
            var path = sys.path()
            path.push(api.wd)
            var hc_display
            if introspect.get(global, 'lv')
                import lvgl_display as _d
                hc_display = _d
            else
                import lcd_display as _d
                hc_display = _d
            end
            path.pop()
            util.scr = hc_display.screen(util, wifi)
            if !configure return end
            util.scr.start_clock()
            # Update zone info
            var z = 0
            while z < size(api.settings.zones)
                var stat = api.settings.zones.get_status(z)
                stat.set_screen()
                z += 1
            end
        end
    end    
    # If DISPlAY option is unset, disable the screen
    def disable_display()
        if util.scr
            util.scr.stop_clock()
            util.scr.clear()
            util.scr = nil
        end
    end
    # Do not call before load() as pixel count needs zone size
    def enable_leds(configure)        
        if api.WS2812 != -1 && api.settings.has('zones')
            var pixels = api.settings.zones.size()
            util.WS2812 = Leds(pixels, api.WS2812)
            if !configure return end
            var z = 0
            while z < size(api.settings.zones)
                api.settings.zones.get_status(z).set_led()
                z += 1
            end
        else
            # WS2812 not configured so disable LED option
            self.set_option(util.options['LED'], false)
        end
    end
    def disable_leds()
        if util.WS2812
            util.WS2812.clear()
            util.WS2812 = nil
        end
    end
    # If sync_webbuttons is true set the relay toggle button to label
    def set_webbutton(btn, label)
        # Don't set the quasi Light/WS2812 button; only relays...
        if btn > api.get_relay_count() return end 
        api.cmd(string.format('webbutton%d %s', btn, label))
    end
    def set_webbuttons()
        var z = 0
        while z < size(api.settings.zones)
            self.set_webbutton(z+1, api.settings.zones.get_label(z))
            z += 1
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
        if !api.settings.has('options')
            api.settings.options = 22 # UI/LED/MQTT enabled
        end
    end
end

# This class is responsible for setting timers - 1 for each schedule
# A timer is set for the on time and reset to the off time when it pops.
class scheduler
    var running
    var schedules
    def init()
        self.running = false
        self.schedules = []
    end
    def start()
        var s = 0
        while s < size(api.settings.schedules)
            self.run_schedule(api.settings.schedules[s])
            s += 1
        end
        var millis = / now -> 60000-now['sec']*1000
        var callback = / formatter, local -> self.on_tick(formatter, local)
        util.set_timer(millis, callback, 'scheduler', true)
        self.on_start()
    end
    def stop()
        self.running = false
        self.schedules.clear()
        api.remove_timer('scheduler')
    end
    # This method is only used when the scheduler is first run.
    # It retrieves statuses for next auto mode run times
    def on_start()
        self.running = true
        var z = 0
        while z < size(api.settings.zones)
            if api.settings.zones.get_mode(z)
                # If mode is override set schedule power state
                var power = api.settings.schedules.get_next_status(z).power
                api.settings.zones.set_power(z, power)
            else
                # Set power states and display/log schedule status
                self.on_completed(z)
            end
            z += 1
        end
    end
    def on_tick(formatter, local)
        var i = 0
        while i < size(self.schedules)
            if self.schedules[i]['runat'] <= local
                var id = self.schedules[i]['id']
                self.schedules.remove(i)
                self.on_pop(api.settings.schedules.get(id))
            else
                i+=1
            end
        end
    end
    def run_schedule(s)
        # Is the schedule switching on or off?
        var power = s.is_running()
        # Get the next run time depending on power state
        var runat = s.get_runat(power ? s.off : s.on)
        # Call on_pop when the timer expires
        self.schedules.push({"id": s[schedule.id], "runat": runat})
    end
    # Called when a schedule on or off time expires/completes
    def on_pop(s)
        if !self.running return end
        # Get the power state for the schedule
        var power = s.is_running()
        # Check each zone for the schedule
        var zone = 0
        while zone < size(api.settings.zones)
            # Is the zone set for this schedule?
            if !s.is_set(s.zones, zone)
                zone += 1
                continue 
            end
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
            zone += 1
        end
        # Force the updated configuration to be saved to flash
        util.config.save()
        # Set the schedule's next switching timer
        self.run_schedule(s)
    end
    def on_completed(zone)
        var stat = util.config.get_next_status(zone)
        # Update the power and expiry/next run time for the zone
        api.settings.zones.set_zone(zone, stat.mode, stat.power, stat.expiry)
        # Set the power state of the relay
        api.set_power(zone, stat.power)
        # Update logs, LED, MQTT and screen
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
        # Update logs, LED, MQTT and screen
        stat.notify()
        # Force the updated configuration to be saved to flash
        util.config.save()
    end
    # turn zone on if off for duration or extend time if on.
    def boost(zone, secs)
        var id = 'boost' .. zone
        var callback = / -> self.on_boost_end(zone)
        var millis = / -> !secs ? 3600000 : secs * 1000
        util.set_timer(millis, callback, id, false)
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
        var zone = 0
        while zone < size(api.settings.zones)
            var mode = api.settings.zones.get_mode(zone)
            if mode == 1
                var expiry = api.settings.zones.get_expiry(zone) - api.rtc()['local']
                self.set(zone, mode, expiry)
            elif mode  > 1
                self.set(zone, mode)
            end
            zone += 1
        end
    end
    # Set the mode for a given zone per flow control map
    def toggle_mode(zone, flow)
        var mode = api.settings.zones.get_mode(zone)
        if !flow.has(mode) return end
        self.set(zone, flow[mode])
    end
end

class driver
    # Called by Tasmota home page to display sensor info
    def web_sensor()
        var msg = ''
        var z = 0
        while z < size(api.settings.zones)
            msg += api.settings.zones[z].sensor
            z += 1
        end
        api.web_send(msg)
    end
    # Called by Tasmota on teleperiod
    def json_append()
        var jsonstr = json.dump(api.settings.zones.tojson())
        var msg = ",\"Zones\":" .. jsonstr
        api.response_append(msg)
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
        self.set_power(zone, mode, v)
    end
    # Change the power state of the zone if different from current state
    def set_power(zone, mode, payload)
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

# Base class for registering commands 
class command
    def init()
        self.add_command()
    end
    def add_command()
        api.add_cmd(self.cmd, / c, i, p, j -> self.on_cmd(c, i, p, j))
    end
    def resp_cmnd(idx, msg)
        var cmd = string.toupper(string.format('%s%d', self.cmd, idx))
        api.resp_cmnd(string.format('{"%s": "%s"}', cmd, msg ? msg : "DONE"))
    end
end

class modes_command: command
    static cmd = "HeatingModes"
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        api.resp_cmnd(json.dump({self.cmd: util.modes}))
    end
end

class days_command: command
    static cmd = "HeatingDays"
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        api.resp_cmnd(json.dump({self.cmd: util.days}))
    end
end

class labels_command: command
    static cmd = "ZoneLabels"
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        var l = []
        for z: 0 .. size(api.settings.zones)-1
            l.push(api.settings.zones.get_label(z))
        end
        api.resp_cmnd(json.dump({self.cmd: l}))
    end
end

# Publishes the status for all options as json payload.
# Updates the status of 1 or more options
# HeatingOptions -> {"HeatingOptions":{"CMD":1,"LED":1,"DISPLAY":1,"SYNC":1,"MQTT":1}}
class options_command: command
    static cmd = "HeatingOptions"
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        if payload_json && isinstance(payload_json, map)
            self.set_options(payload_json)
            self.resp_cmnd()
        elif payload == ''
            var m = {}
            for k: util.options.keys()
                m[k] = util.config.is_option_set(util.options[k]) ? 1 : 0
            end
            api.resp_cmnd(json.dump({self.cmd: m}))
        end
    end
    def set_options(payload)
        var _save = false
        for k: payload.keys()
            var option = util.options.find(string.toupper(k))
            if option
                var new = util.cmd_params.find(string.tolower(str(payload[k])))
                var current = util.config.is_option_set(option)
                if new != nil && current != new
                    util.config.set_option(option, new)
                    _save = true
                end
            end
        end
        if _save util.config.save() end
    end
end

# Publishes the status of all zones as json payload
# zones -> 
# {"Zones": {
#    "Zone3": {"Power":"Off","Label":"WTR","Mode":"Auto","Until":"2022-02-03T16:30:00"},
#    "Zone1": {"Power":"Off","Label":"HTG1","Mode":"Auto","Until":"2022-02-03T16:30:00"},
#    "Zone2": {"Power":"On","Label":"HTG2","Mode":"Day","Until":"2022-02-03T22:00:00"}
# }}
class zones_command: command
    static cmd = 'Zones'
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        var json = json.dump({self.cmd: api.settings.zones.tojson()})
        api.resp_cmnd(json)
    end
end

# Handler for zone command
# zone1 1 -> turn on heating zone 1
# zone2 0 -> turn off heating zone 2
# zone3 {update: {"mode": 5}} -> If not in Day mode, switch to Day mode
# zone3 {update: {"mode": 1, "hours": 2}} -> Boost zone 3 for 2 hours
# zone {new: {"mode": 4, "label": "HTWR"}} -> The new zone will be created
# zone3 delete -> delete zone 3
class zone_command: command
    static cmd = 'Zone'
    def init() super(self).init() end
    def get_mode(zone)
        return api.settings.zones.get_mode(zone)
    end
    def on_cmd(cmd, idx, payload, payload_json)
        idx-=1
        if idx < 0 || idx > api.settings.zones.size()-1
            api.resp_cmnd(json.dump({self.cmd: nil}))
            return
        end
        if isinstance(payload_json, map)
            for k: ['new', 'update']
                var key = util.find_key_i(payload_json, k)
                if key && isinstance(payload_json[key], map)
                    var z
                    try z = zone.fromjson(payload_json[key])
                    except 'assert_failed' as e, m
                        self.resp_cmnd(idx+1, m)
                        return
                    end
                    if k == 'new'
                        self.new(z)
                        self.resp_cmnd()
                        return
                    elif k == 'update'
                        self.update(idx, z)
                    end
                    break
                end
            end
        elif payload == string.tolower("delete")
            self.delete(idx)
        elif payload == ''
            var zone = api.settings.zones[idx].tojson()
            zone['id'] = idx+1
            api.resp_cmnd(json.dump({self.cmd: zone}))
            return
        else
            var power = util.cmd_params.find(string.tolower(payload))
            if power != nil 
                self.set_power(idx, power) 
            end
        end
        self.resp_cmnd(idx+1)
    end
    def new(payload)
        var idx = api.settings.zones.size()
        # Process label
        if !size(payload[zone.label])
            payload[zone.label] = 'ZN' .. idx+1
        end
        # Add the new zone to the zones collection
        api.settings.zones.push(zone(payload))
        # Add the new zone to schedules
        api.settings.schedules.set_zone(idx)
        # Sync button and relay triggers
        util.buttons.add_trigger(idx)
        util.relays.add_trigger(idx)
        # Sync the Tasmota UI Toggle buttons
        if util.config.is_option_set(util.options['SYNC'])
            util.config.set_webbutton(idx+1, payload[zone.label])
        end
        # Process mode and force update as this is a new zone
        self.set_mode(idx, payload, true)
        if payload[zone.mode]
            # If mode is override set schedule power state
            var power = api.settings.schedules.get_next_status(idx).power
            api.settings.zones.set_power(idx, power)
        end
        util.config.save()
    end
    def update(idx, payload)
        # Process label
        var _dirty = false
        var label = payload.find(zone.label)
        if label
            # Only update the label if it has changed
            if size(label) > 0 && label != api.settings.zones.get_label(idx)
                api.settings.zones.set_label(idx, label)
                _dirty = true
                    # Sync the Tasmota UI Toggle buttons
                if util.config.is_option_set(util.options['SYNC'])
                    util.config.set_webbutton(idx+1, label)
                end
            end
        end
        # Process mode
        var mode = payload.find(zone.mode)
        # Only update the mode if it has changed
        if mode != nil && mode != api.settings.zones.get_mode(idx)
            self.set_mode(idx, payload)
            _dirty = false
        end
        # There are updates so update the display and pub to MQTT
        if _dirty
            var stat = api.settings.zones.get_status(idx)
            stat.set_screen()
            stat.pub_mqtt()
            stat.set_sensor()
            util.config.save()
        end
    end
    def delete(idx)
        # Check boost.If active cancel...
        if api.settings.zones.get_mode(idx) == 1
            util.override.on_boost_cancel(idx)
        end
        # Remove last button and relay triggers
        util.buttons.pop_trigger()
        util.relays.pop_trigger()
        # Clear display zone info BEFORE delete
        if util.scr
            for z: api.settings.zones.keys()
                util.scr.clear_zone(z)
            end
        end
        # Remove zone from zone collection
        api.settings.zones.pop(idx)
        # Remove zone from schedules
        api.settings.schedules.remove_zone(idx)
        # Re-sync power state for reshuffled zones
        for z: api.settings.zones.keys()
            var stat = api.settings.zones.get_status(z)
            # Set the power state of the relay
            api.set_power(z, stat.power)
            # Notify display etc.
            stat.notify()
        end
        # Sync the Tasmota UI Toggle buttons
        if util.config.is_option_set(util.options['SYNC'])
            util.config.set_webbuttons()
        end
        util.config.save()
    end
    # Change the operating mode for the zone if different from current mode
    def set_mode(idx, payload, force)
        var to_mode = payload[zone.mode]
        if !force && to_mode == self.get_mode(idx) return end
        if to_mode == 1
            util.override.set(idx, to_mode, payload[zone.expiry])
        else
            util.override.set(idx, to_mode)
        end
    end
    # Change the power state of the zone if different from current state
    def set_power(idx, to_power)
        var mode = self.get_mode(idx)
        var from_power = api.settings.zones.get_power(idx, mode)
        # XOR returns true if power needs toggling
        if from_power ? !to_power : to_power
            # Toggle Advance/Auto
            if mode == 0 || mode == 4
                util.override.toggle_mode(idx, {0:4,4:0})
            # Toggle Const On/Off
            elif mode == 2 || mode == 3
                util.override.toggle_mode(idx, {2:3,3:2})
            # Toggle Boost or Day 
            elif mode == 1 || mode == 5
                # Switch to Advance mode if Auto doesn't toggle power
                if api.settings.zones.get_power(idx) ? !to_power : to_power
                    util.override.set(idx, 4)
                else
                    util.override.set(idx, 0)
                end
            end
        end
    end
end

class schedules_command: command
    static cmd = 'Schedules'
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        var json = json.dump({self.cmd: api.settings.schedules.tojson()})
        api.resp_cmnd(json)
    end
end

# Handler for schedule command
# schedule1  -> return schedule1
# schedule3 {update: {"on":"06:30","zones":[1,1,1],"days":[0,1,1,1,1,1,0],"off":"08:30"}}
# zone {new: {"mode": 4, "label": "HTWR"}} -> The new zone will be created
# zone3 delete -> delete zone 3
class schedule_command: command
    static cmd = 'Schedule'
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        if idx < 1 || idx > api.settings.schedules.size()
            api.resp_cmnd(json.dump({self.cmd: nil}))
            return
        end
        if isinstance(payload_json, map)
            for k: ['new', 'update']
                var key = util.find_key_i(payload_json, k)
                if key && isinstance(payload_json[key], map)
                    payload_json[key].setitem('id', idx)
                    try payload_json = schedule.fromjson(payload_json[key])
                    except 'assert_failed' as e, m
                        self.resp_cmnd(idx, m)
                        return
                    end
                    if k == 'new'
                        self.new(payload_json)
                        self.resp_cmnd()
                        return
                    elif k == 'update'
                        self.update(payload_json)
                    end
                    break
                end
            end
        elif payload == string.tolower("delete") && idx > 0
            self.delete(idx)
        elif payload == ''
            var json = json.dump({self.cmd: api.settings.schedules.get(idx).tojson()})
            api.publish_result(json)
            return
        end
        self.resp_cmnd(idx)
    end
    def new(payload)
        if api.settings.schedules.push(payload) util.restart() end
    end
    def update(payload)
        if api.settings.schedules.update(payload) util.restart() end
    end
    def delete(idx)
        if api.settings.schedules.pop(idx) util.restart() end
    end
end

# The main class for setting up the heating controller
class HeatingController
    def init()
        self._start()
    end
    # Start the heating controller
    def _start()
        # Create the configuration capability
        util.config = config()
        # Load persisted zones, schedules and options
        util.config.load()
        # Register commands
        zone_command()
        zones_command()
        schedule_command()
        schedules_command()
        options_command()
        modes_command()
        days_command()
        labels_command()
        # Restoe configuration options
        util.config.configure_options()
        # Create the override capability
        util.override = override()
        # Create the scheduler capability
        util.scheduler = scheduler()
        # Create a tasmota driver
        util.driver = driver()
        # Register the tasmota driver
        api.add_driver(util.driver)
        # Fires when wifi connects
        api.add_rule("Wifi#Connected", /-> wifi.set_status(true))
        # Fires when wifi disconnects
        api.add_rule("Wifi#Disconnected", /-> wifi.set_status(false))
        # Fires when RTC has initialized 
        api.add_rule('Time#Initialized', /  -> self.time_initialized())
        # Fires when MQTT has connected
        api.add_rule('Mqtt#Connected', /  -> self.mqtt_connected())
        # Register button press triggers
        util.buttons = buttons()
        # Register power state change triggers
        util.relays = relays()
    end
    # Called once the RTC is initialized (Time#Initialized)
    def time_initialized()
        # Restore override state
        util.override.refresh()
        # Start the scheduler
        util.scheduler.start()
        # If a display is configured, show the time
        if util.scr
            util.scr.start_clock()
        end
    end
    # When MQTT connects send heating status for all zones
    def mqtt_connected()
        if util.config.is_option_set(util.options['MQTT'])
            var z = 0
            while z < size(api.settings.zones)
                api.settings.zones.get_status(z).pub_mqtt()
                z += 1
            end
        end
    end    
end

heating.controller = HeatingController
return heating
