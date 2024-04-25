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
    static def strftime(fmt, secs)
        return tasmota.strftime(fmt, secs)
    end
    static def strptime(time, fmt)
        return tasmota.strptime(time, fmt)
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
    static def set_timer(millis, func, id)
        tasmota.set_timer(millis, func, id)
    end
    static def remove_timer(id)
        tasmota.remove_timer(id)
    end
    static def add_cron(cron, func, id)
        tasmota.add_cron(cron, func, id)
    end
    static def remove_cron(id)
        tasmota.remove_cron(id)
    end
    static def next_cron(id)
        return tasmota.next_cron(id)
    end
    static def get_power()
        return tasmota.get_power()
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
    static def publish_result(payload, subtopic)
        var _subtopic = subtopic ? subtopic : "RESULT"
        tasmota.publish_result(payload, _subtopic)
    end
    # Find a key in map, case insensitive
    # Returns key or nil if not found
    static def find_key_i(m, keyi)
        return tasmota.find_key_i(m, keyi)
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
        0x00FF00, # Green
        0x800080, # Purple
        0x088F8F, # Dark Cyan
        0xFF00FF, # Magenta
        0x0000FF, # Blue
        0xf58231  # Yellow
    ]
    # --------------------------------------------------------------------------------------------------
    # DISPLAY:  Enable support for I2C LCD 20x4/20x2 display or SPI 320x240 ILI9341 (default: false)
    # UI:  Enable web UI - requires hc_wgui.tapp (default: true)
    # LED:  Enable addressable LED indicator lights (WS2812 pin needs to be set) (default: true)
    # THERMC: Enable thermostat integration (default: false)
    # MQTT: Enable the publishing of MQTT heating zone telemetry (default: true)
    # --------------------------------------------------------------------------------------------------
    static options = {
        'DISPLAY': 1, # 1 << 0
        'UI': 2, # 1 << 1
        'LED': 4, # 1 << 2
        'THERM': 8, # 1 << 3
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
    # Enable access to WS2812 LEDs
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
    # The alexa class handles comms with Alexa
    static alexa = nil
end

class disp
    static def publish(payload)
        api.publish_result(json.dump({'HeatingDisplay': payload}))
    end
end

class ui
    static initialised = false
    static def publish(payload)
        api.publish_result(json.dump({'HeatingUI': payload}))
    end
end

class time
    static def round(time, interval)
        var offset = time % interval
        var rounded = time - offset
        if offset > interval/2
          return rounded + interval
        else
          return rounded
        end
    end
end

# A status contains information about the current state of a zone
class status
    var zone, mode, power, expiry, label, key, state, target
    # @param zone: index of zone from api.settings.zones
    # @param mode: which mode the zone is currently set to
    # @param power: on/off state of zone
    # @param expiry: next on/off time for auto or expiry for boost
    # @param target: target temperature (from zone or schedule)
    def init(zone, mode, power, expiry, target)
        self.zone = zone
        self.label = api.settings.zones.get_label(self.zone)
        self.mode = mode
        self.key = util.modes[self.mode]
        self.power = power
        self.state = self.power ? 'On' : 'Off'
        self.expiry = expiry
        self.target = target
    end
    # Publishes a payload to trigger a display update
    def update_display()
        if !util.config.is_option_set(util.options['DISPLAY']) return end
        disp.publish(self.tojson())
        api.settings.zones.pub_heat(self.zone)
    end
    # WS2812 LED (1 pixel per zone) indicator
    def set_led()
        if !util.config.is_option_set(util.options['LED']) return end
        var color = self.power ? util.colors[self.mode] : 0xFF0000
        util.WS2812.set_pixel_color(self.zone, color)
        util.WS2812.show()
    end
    # Set the relay power state
    def set_relay()
        # Only set the power on if room temp < target temp
        api.settings.zones.set_relay(self.zone, self.power)
    end
    # Update Alexa power state
    def set_alexa()
        if util.alexa
            util.alexa.set_power(self.zone, self.power)
        end
    end
    # zone.target_temp will be set to zone or schedule 't' field
    def set_target()
        api.settings.zones[self.zone].set_target_temp(self.target)
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
        if ui.initialised && util.config.is_option_set(util.options['UI'])
            linkstart = '<a href="/hm">'
            linkend = '</a>'
        end
        var fmt = 12&(1<<self.mode)
            ? '{s}%s%s %s%s{m}Const Mode{e}'
            : '{s}%s%s %s until %%a %%R%s{m}%s Mode{e}'
        var msg =  api.strftime(
            string.format(
                fmt, 
                linkstart, 
                self.label, 
                self.state, 
                linkend, 
                self.key
            ), 
            self.expiry
        )
        api.settings.zones[self.zone].sensor = msg
    end
    # Update logs, LED, MQTT and screen
    def notify()
        self.set_target()
        self.set_sensor()
        self.set_led()
        self.set_relay()
        self.pub_mqtt()
        self.update_display()
        self.set_alexa()
    end
    # Helper map for self.pub_mqtt()
    def tojson()
        var zjs = api.settings.zones[self.zone].tojson(self.zone)
        return {"HeatingZone":  zjs}
    end
end

# This class represents a single heating zone
# zone['l'] = label
# zone['e'] = expiry
# zone['m'] = mode (6 bit for previous & current)
# zone['p'] = power (2 bit for auto & override)
# zpne['t'] = target temperature (optional) when THERM enabled
# zone['r'] = room temperature (optional) when THERM enabled
class zone: map
    static label = 'l', expiry = 'e', mode = 'm', power = 'p', room = 'r', target = 't'
    # The scheduler will set zone.target to schedule[schedule.target] when schedule starts
    # The scheduler will set zone.target to zone[zone.target] when schedule stops
    var sensor, target_temp
    def init(o)
        self.sensor = ''
        super(self).init()
        o = isinstance(o, map) ? o : {"l": o?o:'' ,"e": 0, "m": 0, "p": 0}
        for k: o.keys()
            self[k] = o[k]
        end
        self.target_temp = self.get_temp(zone.target)
    end
    # validates json payload values if keys present:
    # {"label": "Zone 1", "mode": 0} or {"label": "Zone 1", "mode": 1, "hours": 2}
    # If validation successful returns a zone map else raises an assert_failed error 
    static def fromjson(m, action)
        # If payload is from an update return only keys updated
        var z = action == 'update' ? {} : zone()
        var msg = / s -> string.format("Error: %s invalid or missing", s)
        for k: m.keys()
            var key = string.tolower(k)
            if key == 'label'
                assert(type(m[k]) == 'string', msg(k))
                z[zone.label] = m[k]
            elif key == 'mode'
                assert(type(m[k]) == 'int', msg(k))
                assert(m[k] >=0 && m[k] < size(util.modes), msg(k)) 
                z[zone.mode] = m[k]
            elif key == 'hours'
                assert(type(m[k]) == "int", msg(k))
                assert(m[k] == 1 || m[k] == 2, msg(k))
                # hours is not a member of zone so convert to expiry
                z[zone.expiry] = m[k] * 3600
            elif (key == 'target' || key == 'room') && util.config.is_option_set(util.options['THERM'])
                if m[k] != nil
                    assert(type(m[k]) == "int" || type(m[k]) == "real", msg(k))
                end
                z[key == 'target' ? zone.target : zone.room] = m[k]
            end
        end
        if z.contains(zone.mode) && z[zone.mode] == 1
            # If mode is boost then expiry should be present AND should be > 0
            assert(z.contains(zone.expiry), msg('hours'))
            assert(z[zone.expiry] > 0, msg('hours'))
        end
        return z
    end
    def get_temp(field)
        return self.find(field)
    end
    def set_temp(field, temp)
        if self.get_temp(field) != temp
            if temp != nil
                self[field] = temp
            else
                self.remove(field)
            end
            return true
        end
    end
    def set_target_temp(temp)
        # Only use a schedule target temp if mode is Auto or Day
        var auto_or_day = 33 & (1<<self.get_mode())
        if auto_or_day && self.get_power() && temp
            self.target_temp = temp
        else
            self.target_temp = self.get_temp(zone.target)
        end
    end
    def heat()
        var target = self.target_temp
        var room = self.get_temp(self.room)
        if target != nil && room != nil
            return room < target
        end
        return true
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
    def get_info(m)
        var fmt = 12&(1<<m)
            ? '%s Const %s' 
            : '%s %s %s until %%H:%%M %%a %%d %%b %%y'
        return api.strftime(string.format(fmt, 
            self[self.label], 
            util.modes[m], 
            self.get_power(m) ? 'On' : 'Off'), self[self.expiry])
    end
    def tojson(idx)
        var m = self.get_mode()
        var z = {
            "id":  idx+1,
            "label": self[self.label],
            "mode": m,
            "power": self.get_power(m),
            "expiry": 12&(1<<m) ? 0 : self[self.expiry],
            "info": self.get_info(m)
        }
        if util.config.is_option_set(util.options['THERM'])
            z["target temp"] = self.get_temp(self.target)
            z["room temp"] = self.get_temp(self.room)
        end
        return z
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
    # Set relay state (considering temp if THERM option is set)
    def set_relay(z, p)
        p = p != nil ? p : self[z].get_power(self[z].get_mode())
        var h = util.config.is_option_set(util.options['THERM'])
            ? self[z].heat() 
            : true
        api.set_power(z, p && h)
    end
    def pub_heat(z)
        if !util.config.is_option_set(util.options['DISPLAY']) 
            return
        end
        var ht = {
            "zone": z+1,
            "heat": api.get_power()[z]
        }
        if util.config.is_option_set(util.options['THERM'])
            ht["target temp"] = self[z].target_temp
            ht["room temp"] = self[z].get_temp(zone.room)
        end
        disp.publish({"HeatingStatus": ht})
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
        var t = self[z].get_temp(zone.target)
        return status(z, m, p, e, t)
    end
    def tojson()
        var l = []
        for k: self.keys()
            var jsz = self[k].tojson(k)
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
    static on = '1', off = '0', id = 'i', days = 'd', zones = 'z', target = 't'
    def init(m)
        super(self).init()
        m = isinstance(m, map) ? m : {"i":0, "1":0, "0":0, "d":127, "z":0}
        for k: m.keys()
            self[k] = m[k]
        end
    end
    # validates if a json payload is in the following format:
    # {"on": "07:00", "off": "12:59", "id":3, "days": [0,1,1,1,1,1,0], "zones":[1,1,0]}
    # If validation successful returns a schedule instance else raises an assert_failed error 
    static def fromjson(m, action)
         # Fill a default schedule with all days, and zones selected for a new schedule
        var sum = (1 << api.settings.zones.size())-1
        var sched = action == 'update' ? {} : schedule({"i":0, "1":0, "0":1, "d":127, "z": sum})
        var msg = / k, s -> string.format("Error: %s key %s", k, s ? s : "invalid")
        for k: m.keys()
            var key = string.tolower(k)
            if key == 'on' || k == 'off'
                var t = api.strptime(m[k], '%H:%M')
                assert(t && t['hour']<24 && t['min']<60, msg(k, "must be hh:mm format"))
                sched[key == 'on' ? schedule.on : schedule.off] = t['hour']*3600+t['min']*60
            elif key == 'id'
                assert(type(m[k]) == 'int', msg(k))
                sched[schedule.id] = m[k]
            elif key == 'days' || k == 'zones'
                assert(classname(m[k]) == 'list', msg(k, "must be a list"))
                var l = key == 'days' ? 7 : api.settings.zones.size()
                assert(size(m[k]) == l, msg(k, "has incorrectly sized list"))
                var x = 0
                for lk: m[k].keys()
                    var v = m[k][lk]
                    assert(v == 0 || v == 1, msg(k, "must have list items of 1 or 0"))
                    if v x+= (1 << lk) end
                end
                assert(x > 0, msg(k, "must contain at leat one " .. k[0..-2]))
                sched[key == 'days' ? schedule.days : schedule.zones] = x
            elif key == 'target' && util.config.is_option_set(util.options['THERM'])
                if m[k] != nil
                    assert(type(m[k]) == "int" || type(m[k]) == "real", msg("target"))
                end
                sched[schedule.target] = m[k]
            end
        end
        var x = sched.contains(schedule.on)
        var y = sched.contains(schedule.off)
        assert( !((x || y) && (!x || !y)), msg('on and off', "are both required"))
        if x && y
            assert(sched[schedule.off] > sched[schedule.on], msg("off", "must be later than on key"))
        end
        return sched
    end
    # true if index i of list k (days/zones) is set
    def is_set(k, i)
        return !!(self[k] & (1 << i))
    end
    def set_zone(zone)
        self[self.zones] += (1 << zone)
    end
    def get_target_temp()
        return self.find(self.target)
    end
    def set_target_temp(temp)
        if self.get_target_temp() != temp
            self[self.target] = temp
            return true
        end
    end
    def remove_zone(zone)
        var mask = -1 << zone
        var x = self[self.zones]
        self[self.zones] = ((x ^ (x >> 1)) & mask) ^ x
    end
    # Converts a string time to seconds from midnight
    # E.g., 10:15 -> 10x3600 + 15x60 
    def str2secs(tstr)
        var hours = int(tstr[0..1])
        var mins = int(tstr[3..4])
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
    # Runat times will ALWAYS be 'on the minute'
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
        var runat = ( i ? 86400*i-(sfm-t) : t-sfm) + now['local']
        # Ensure that runat time is 'on the minute' exactly
        return time.round(runat, 60)
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
        for k: o.keys()
            if o[k] != self[k]
                return false
            end
        end
        return true
    end
    def != (o)
        return !self==(o)
    end
    def tojson()
        var s =  {
            "on": self.secs2str(self[self.on]),
            "off": self.secs2str(self[self.off]),
            "id": self[self.id],
            "days": self.days2list(),
            "zones": self.zones2list()
        }
        if util.config.is_option_set(util.options['THERM'])
            s["target temp"] = self.find(self.target)
        end
        return s
    end
end

# List of all schedules
class schedules : list
    def init(l)
        super(self).init()
        if isinstance(l, list)
            for s: l
                self.push(schedule(s), true)
            end
        end
    end
    # list.push overridden to take a schedule
    def push(schedule, assignid)
        if assignid
            schedule[schedule.id] = self.next_id()
        end
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
    # Gets schedule.target temp for schedule
    def get_target_temp(id)
        var sched = self.get(id)
        if sched
            return sched.get_target_temp()
        end
    end
    # Sets schedule.target_temp temp
    def set_target_temp(id, temp)
        var sched = self.get(id)
        if sched
            return sched.set_target_temp(temp)
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
    # Updates all or sub-set of schedule fields 
    def update(updated)
        var current = self.get(updated[schedule.id])
        if current
            if current == updated
                return false
            else 
                for k: updated.keys()
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
                    var t = s.get_target_temp()
                    return status(zone, 0, true, r, t)
                else 
                    i = r < i ? r : i 
                end
            end
        end
        return status(zone, 0, false, i, nil)
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
        for sched: self
            l.push(sched.tojson())
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
        elif opt == util.options['UI']
            self.toggle_ui(set)
        elif opt == util.options['THERM']
            self.update_therm()
        end
    end
    # Configures options - called by HeatingController on startup
    def configure_options()
        self.configure_option(
            util.options['LED'], 
            self.is_option_set(util.options['LED'])
        )
    end
    # If UI option is set, enable the Tasmota UI
    # Obviously if the UI is disabled from the UI it can
    # only be re-enabled via the HeatingOptions command
    def toggle_ui(enable)
        ui.publish(enable ? "ON" : "OFF")
        for z: api.settings.zones.keys()
            # Remove hyperlink to web ui if ui disabled
            var stat = api.settings.zones.get_status(z)
            stat.set_sensor()
        end
    end
    # If DISPLAY option is set, enable the screen 
    # (if display tapp loads before controller)
    def enable_display(configure)
        disp.publish("ON")
        if !configure return end
        # Give the display a chance to initialise as on is async
        api.set_timer(2000, 
            def()
                for z: 0 .. size(api.settings.zones)-1
                    var stat = api.settings.zones.get_status(z)
                    stat.update_display()
                end
            end
        )
    end
    # If DISPlAY option is unset, disable the screen
    def disable_display()
        disp.publish("OFF")
    end
    # If THERN option changes, relay & display needs updating
    def update_therm()
        for z: api.settings.zones.keys()
            api.settings.zones.set_relay(z)
            # Needs to be a deferred call as nested pubs blocked
            api.set_timer(0, /->api.settings.zones.pub_heat(z))
        end
    end
    # Do not call before load() as pixel count needs zone size
    def enable_leds(configure)        
        if api.WS2812 != -1 && api.settings.has('zones')
            var pixels = api.settings.zones.size()
            util.WS2812 = Leds(pixels, api.WS2812)
            if !configure return end
            for z: 0 .. size(api.settings.zones)-1
                api.settings.zones.get_status(z).set_led()
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
    # Saves the configuration to _persist.json
    def save()
        api.settings.save()
    end
    # Loads zones, schedules and options from _persist.json
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
    def restart()
        util.scheduler.stop()
        util.scheduler.start()
        self.refresh()
    end
    # Refreshes zones on re/start or schedue/zone changes
    # Refreshes scheduler/override depending on mode of each zone
    def refresh()
        for zone: 0 .. size(api.settings.zones)-1
            var mode = api.settings.zones.get_mode(zone)
            if mode == 0
                # Process schedule/auto zone
                util.scheduler.refresh(zone)
            else
                # If mode is override set schedule power state
                var power = api.settings.schedules.get_next_status(zone).power
                api.settings.zones.set_power(zone, power)
                # Process override zone
                util.override.refresh(zone, mode)
            end
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
        api.add_cron("0 * * * * *", / now -> self.on_tick(now), 'scheduler')
        self.running = true
    end
    def stop()
        self.running = false
        self.schedules.clear()
        api.remove_cron('scheduler')
    end
    # This method is only used when the scheduler is re/started
    # It publishes info for next auto mode run times
    def refresh(zone)
        self.on_completed(zone)
    end
    def on_tick(local)
        var i = 0
        while i < size(self.schedules)
            if self.schedules[i]['runat'] <= local
                var id = self.schedules[i]['id']
                # Running always alternates between on and off
                var running = !self.schedules[i]['running']
                self.schedules.remove(i)
                self.on_pop(api.settings.schedules.get(id), running)
            else
                i+=1
            end
        end
    end
    def run_schedule(s)
        # Is the schedule switching on or off?
        var running = s.is_running()
        # Get the next run time depending on power state
        var runat = s.get_runat(running ? s.off : s.on)
        # Add to list of running schedules
        self.schedules.push({"id": s[schedule.id], "running": running, "runat": runat})
    end
    def get_running_schedules()
        var rsl =  schedules()
        for rs: self.schedules
            if rs['running']
                rsl.push(api.settings.schedules.get(rs['id']))
            end
        end
        return rsl
    end
    def get_running_schedule(zone_idx)
        # Only return a running schedule if zone mode is auto (0)
        if api.settings.zones[zone_idx].get_mode() return end
        for s: self.get_running_schedules()
            if s.is_set(schedule.zones, zone_idx)
                return s
            end
        end
    end
    # Called when a schedule on or off time expires/completes
    def on_pop(s, running)
        if !self.running return end
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
                api.settings.zones.set_zone(zone, previous, running)
                self.on_completed(zone)
            elif mode == 5 # Daytime
                # If schedule matches first on/last off, update power, expriry etc
                if util.override.check_day(zone, s, running) 
                    self.on_completed(zone)
                end
                # Update schedule power
                api.settings.zones.set_power(zone, running)
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
    end
    # Before the mode is changed, check if we need to cancel a running boost
    def check_boost(zone, mode)
        var current = api.settings.zones.get_mode(zone)
        if mode != current && current == 1
            self.on_boost_cancel(zone)
        end
    end
    # Set the relay power state and log/display message for zone
    def on_completed(zone, target_temp)
        var stat = api.settings.zones.get_status(zone)
        # Day mode pass a target_temp param
        if target_temp 
            stat.target = target_temp 
        end
        # Update logs, LED, MQTT and screen
        stat.notify()
        # Force the updated configuration to be saved to flash
        util.config.save()
    end
    # turn zone on if off for duration or extend time if on.
    def boost(zone, secs)
        var callback = / -> self.on_boost_end(zone)
        var millis = !secs ? 3600000 : secs * 1000
        api.set_timer(millis, callback, 'boost' .. zone)
        var expiry = (!secs ? 3600 : secs) + api.rtc()['local']
        api.settings.zones.set_zone(zone, 1, true, expiry)
        self.on_completed(zone)
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
    end
    # Toggle zone state
    def advance(zone)
        var stat = api.settings.schedules.get_next_status(zone)
        api.settings.zones.set_zone(zone, 4, !stat.power, stat.expiry)
        self.on_completed(zone)
    end
    # Swtich zone to timer mode. Let scheduler handle on_completed()
    def auto(zone)
        api.settings.zones.set_mode(zone, 0)
        util.scheduler.on_completed(zone)
        util.config.save()
    end
    # Switch zone permanently on
    def on(zone)
        api.settings.zones.set_zone(zone, 2, true)
        self.on_completed(zone)
    end
    # Switch zone permanently off
    def off(zone)
        api.settings.zones.set_zone(zone, 3, false)
        self.on_completed(zone)
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
        var expiry, target_temp
        if power 
            expiry = off
            target_temp = finish.get_target_temp()
        elif n['sfm'] < start[start.on] 
            expiry = on
            target_temp = start.get_target_temp()
        elif n['sfm'] >= finish[finish.off]
            var nfo = api.settings.schedules.get_next_first_on(zone, n['weekday'])
            expiry = nfo.get_runat(nfo.on)
            target_temp = nfo.get_target_temp()
        end
        api.settings.zones.set_zone(zone, 5, power, expiry)
        if !_dt
            self.on_completed(zone, target_temp)
        end
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
    # Refresh overrides for all zones on re/start or schedule/zone changes.
    def refresh(zone, mode)
        if mode == 1 # Boost
            var expiry = api.settings.zones.get_expiry(zone) - api.rtc()['local']
            self.set(zone, mode, expiry)
        elif mode  > 1  # All other override modes
            self.set(zone, mode)
        end
    end
    # Set the mode for a given zone per flow control map
    def exec_flow(zone, flow)
        var mode = api.settings.zones.get_mode(zone)
        if !flow.has(mode) return end
        self.set(zone, flow[mode])
    end
    def toggle_zone(zone, to_power)
        to_power = int(to_power)
        var mode = api.settings.zones.get_mode(zone)
        var from_power = api.settings.zones.get_power(zone, mode)
        # XOR returns true if power needs toggling
        if (to_power == 1 || to_power == 0) && (from_power ? !to_power : to_power)
            # Toggle Advance/Auto
            if mode == 0 || mode == 4
                self.exec_flow(zone, {0:4,4:0})
            # Toggle Const On/Off
            elif mode == 2 || mode == 3
                self.exec_flow(zone, {2:3,3:2})
            # Toggle Boost or Day 
            elif mode == 1 || mode == 5
                # Switch to Advance mode if Auto doesn't toggle power
                if (int(api.settings.zones.get_power(zone)) ^ to_power)
                    self.set(zone, 4)
                else
                    self.set(zone, 0)
                end
            end
        end
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
        var msg = ''
        var z = 0
        while z < size(api.settings.zones)
            var jsonstr = json.dump(api.settings.zones[z].tojson(z))
            msg += string.format(",\"HeatingZone%s\":%s", z+1, jsonstr)
            z += 1
        end
        api.response_append(msg)
    end
end

class alexa
    static callback = / z, p -> util.override.toggle_zone(z, p)
    def init(zones)
        import hue_bridge
        for z: 1 .. size(zones)
            self.add_device(z, zones[z-1][zone.label])
        end
    end
    # Alexa device id must be > 0 (zone idx+1)
    def add_device(id, label)
        var d = self.device()
        hue_bridge.add_light(id, d, label)
    end
    # Remove Alexa device by Alexa device id (zone idx-1)
    def remove_device(id)
        hue_bridge.remove_light(id)
    end
    def device()
        class heating_state: light_state
            def init(id)
                super(self).init(light_state.RELAY)
            end
            def signal_change()
                var zone = hue_bridge.light_to_id(self) - 1
                alexa.callback(zone, self.power)
            end
        end
        return heating_state()
    end
    def set_power(zone, power)
        hue_bridge.lights[zone+1]['light'].set_power(power)
    end
end

class buttons
    static fmt = 'Button%d#Action'
    def init()
        self.add_triggers()
    end
    def add_trigger(zone)
        # Run deferred as nested rules are blocked...
        api.add_rule(
            string.format(self.fmt, zone+1), 
            / v, t -> api.set_timer(0, / -> self.on_changed(v, t))
        )
    end
    def add_triggers()
        for i: api.settings.zones.keys()
            self.add_trigger(i)
        end
    end
    def pop_trigger()
        api.remove_rule(
            string.format(self.fmt, api.settings.zones.size())
        )
    end
    # Handler for physical buttons
    def on_changed(v, t)
        var zone = int(t[6])-1
        if v == 'SINGLE'
            util.override.exec_flow(zone, {0:4,4:0})
        elif v == 'DOUBLE'
            util.override.exec_flow(zone, {0:5,5:2,2:3,3:0})
        elif v == 'TRIPLE'
            util.override.exec_flow(zone, {0:1,1:0})
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
    def resp_cmnd(msg, idx)
        var cmd = string.format('%s%d', self.cmd, idx)
        api.resp_cmnd(json.dump({cmd: msg != nil ? msg : "DONE"}))
    end
end

class running_command: command
    static cmd = "RunningSchedules"
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        var j = util.scheduler.get_running_schedules().tojson()
        self.resp_cmnd(j)
    end
end
class modes_command: command
    static cmd = "HeatingModes"
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        self.resp_cmnd(util.modes)
    end
end

class days_command: command
    static cmd = "HeatingDays"
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        self.resp_cmnd(util.days)
    end
end

class labels_command: command
    static cmd = "HeatingLabels"
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        var l = []
        for z: 0 .. size(api.settings.zones)-1
            l.push(api.settings.zones.get_label(z))
        end
        self.resp_cmnd(l)
    end
end

# Publishes the status for all options as json payload.
# Updates the status of 1 or more options
# HeatingOptions -> {"HeatingOptions":{"CMD":1,"LED":1,"DISPLAY":1,"THERM":1,"MQTT":1}}
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
            self.resp_cmnd(m)
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
# HeatingZones -> 
# {"HeatingZones": [
#    {"id":1,"label":"GROUND","expiry":1651595400,"info":"GROUND Auto Off until 16:30 Tue 03 May 22","power":false,"mode":0},
#    {"id":2,"label":"FIRST","expiry":1651615200,"info":"FIRST Day On until 22:00 Tue 03 May 22","power":true,"mode":5},
#    {"id":3,"label":"WATER","expiry":1651595400,"info":"WATER Auto Off until 16:30 Tue 03 May 22","power":false,"mode":0}
# ]}
class zones_command: command
    static cmd = 'HeatingZones'
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        self.resp_cmnd(api.settings.zones.tojson())
    end
end

# Handler for HeatingZone command
# HeatingZone1 1 -> turn on heating zone 1
# HeatingZone2 0 -> turn off heating zone 2
# HeatingZone3 {update: {"mode": 5}} -> If not in Day mode, switch to Day mode
# HeatingZone3 {update: {"mode": 1, "hours": 2}} -> Boost zone 3 for 2 hours
# HeatingZone {new: {"mode": 4, "label": "HTWR"}} -> The new zone will be created
# HeatingZone3 delete -> delete zone 3
class zone_command: command
    static cmd = 'HeatingZone'
    def init() super(self).init() end
    def get_mode(zone)
        return api.settings.zones.get_mode(zone)
    end
    def check_idx(idx)
        if idx < 0 || idx > api.settings.zones.size()-1
            self.resp_cmnd('Not Found', idx+1)
            return false
        end
        return true
    end
    def on_cmd(cmd, idx, payload, payload_json)
        idx-=1
        if isinstance(payload_json, map)
            for k: ['new', 'update']
                var key = api.find_key_i(payload_json, k)
                if key && isinstance(payload_json[key], map)
                    var z
                    try z = zone.fromjson(payload_json[key], k)
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
        else
            payload = string.tolower(payload)
        end
        if !self.check_idx(idx)
            return
        end
        if payload == "delete"
            self.delete(idx)
        elif payload == "runningschedule"
            var jz = api.settings.zones[idx].tojson(idx)
            jz['id'] = idx+1
            var js = util.scheduler.get_running_schedule(idx)
            if js js = js.tojson() end
            api.resp_cmnd(json.dump({self.cmd: jz, "RunningSchedule": js}))
            return
        elif payload == 'heat'
            if api.settings.zones.get_power(idx, self.get_mode(idx))
                api.set_power(idx, true)
                api.settings.zones.pub_heat(idx)
            end
        elif payload == 'idle'
            if api.settings.zones.get_power(idx, self.get_mode(idx))
                api.set_power(idx, false)
                api.settings.zones.pub_heat(idx)
            end
        elif payload == ''
            var zone = api.settings.zones[idx].tojson(idx)
            zone['id'] = idx+1
            self.resp_cmnd(zone)
            return
        else
            var power = util.cmd_params.find(payload)
            if power != nil 
                util.override.toggle_zone(idx, power)
            end
        end
        self.resp_cmnd(nil, idx+1)
    end
    def new(payload)
        var idx = api.settings.zones.size()
        # Process label
        if !size(payload[zone.label])
            payload[zone.label] = 'ZN' .. idx+1
        end
        if payload.contains(zone.target) && payload[zone.target] == nil
            payload.remove(zone.target)
        end
        if payload.contains(zone.room) && payload[zone.room] == nil
            payload.remove(zone.room)
        end
        # Add the new zone to the zones collection
        api.settings.zones.push(zone(payload))
        # Add the new zone to schedules
        api.settings.schedules.set_zone(idx)
        # Now we need to set target_temp
        if payload.contains(zone.target)
            api.settings.zones[idx].set_target_temp(payload[zone.target])
        end
        # Add a new Alexa device
        if util.alexa
            util.alexa.add_device(idx+1, payload[zone.label])
        end
        # Sync button triggers
        util.buttons.add_trigger(idx)
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
        if !self.check_idx(idx)
            return
        end
        # Process temperatures
        def set_temp(f)
            if payload.contains(f)
                return api.settings.zones[idx].set_temp(f, payload[f])
            end
        end
        var target = set_temp(zone.target)
        if target
            api.settings.zones[idx].set_target_temp(payload[zone.target])
        end
        var room = set_temp(zone.room)
        if target || room
            api.settings.zones.set_relay(idx)
            api.settings.zones.pub_heat(idx)
        end
        var _dirty = false
        # Process label
        var label = payload.find(zone.label)
        if label
            # Only update the label if it has changed
            if size(label) > 0 && label != api.settings.zones.get_label(idx)
                api.settings.zones.set_label(idx, label)
                # Update Alexa device name (needs Alexa app rediscoery)
                if util.alexa
                    util.alexa.add_device(idx+1, label)
                end
                _dirty = true
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
            stat.update_display()
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
        # Remove last button triggers
        util.buttons.pop_trigger()
        # Clear display zone info BEFORE delete
        if util.config.is_option_set(util.options['DISPLAY'])
            for z: 1 .. size(api.settings.zones)
                disp.publish({"ClearZone": z})
            end
        end
        # Clear Alexa devices
        if util.alexa
            for id: 1 .. api.settings.zones.size()
                util.alexa.remove_device(id)
            end
        end
        # Remove zone from zone collection
        api.settings.zones.pop(idx)
        # Remove zone from schedules
        api.settings.schedules.remove_zone(idx)
        # Re-create Alexa devices. Will still need Alexa app cleanup
        if util.alexa
            util.alexa = alexa(api.settings.zones)
        end
        # Re-sync power state for reshuffled zones
        for z: 0 .. api.settings.zones.size()-1
            var stat = api.settings.zones.get_status(z)
            # Notify display etc.
            stat.notify()
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
end

class schedules_command: command
    static cmd = 'HeatingSchedules'
    def init() super(self).init() end
    def on_cmd(cmd, idx, payload, payload_json)
        self.resp_cmnd(api.settings.schedules.tojson())
    end
end

# Handler for schedule command
# schedule1  -> return schedule1
# schedule3 {update: {"on":"06:30","zones":[1,1,1],"days":[0,1,1,1,1,1,0],"off":"08:30"}}
# zone {new: {"mode": 4, "label": "HTWR"}} -> The new zone will be created
# zone3 delete -> delete zone 3
class schedule_command: command
    static cmd = 'HeatingSchedule'
    def init() super(self).init() end
    def check_idx(idx)
        if idx < 1 || idx > api.settings.schedules.size()
            self.resp_cmnd('Not Found', idx)
            return false
        end
        return true
    end    
    def on_cmd(cmd, idx, payload, payload_json)
        if isinstance(payload_json, map)
            for k: ['new', 'update']
                var key = api.find_key_i(payload_json, k)
                if key && isinstance(payload_json[key], map)
                    payload_json[key].setitem('id', idx)
                    try payload_json = schedule.fromjson(payload_json[key], k)
                    except 'assert_failed' as e, m
                        self.resp_cmnd(idx, m)
                        return
                    end
                    if k == 'new'
                        self.new(payload_json)
                        self.resp_cmnd()
                        return
                    elif k == 'update'
                        if !self.check_idx(idx)
                            return
                        end
                        self.update(payload_json)
                    end
                    break
                end
            end
        end
        if !self.check_idx(idx)
            return
        end
        if string.tolower(payload) == "delete"
            self.delete(idx)
        elif payload == ''
            var json = json.dump({self.cmd: api.settings.schedules.get(idx).tojson()})
            api.publish_result(json)
            return
        end
        self.resp_cmnd(nil, idx)
    end
    def new(payload)
        if payload.contains(schedule.target) && payload[schedule.target] == nil
            payload.remove(schedule.target)
        end
        if api.settings.schedules.push(payload, true) util.config.restart() end
    end
    def update(payload)
        # Handle updated target temp for schedule
        var target = payload.find(zone.target)
        if target
            var id = payload[schedule.id]
            if api.settings.schedules.set_target_temp(id, target)
                # If schedule currently running force a relay upate
                var rs = util.scheduler.get_running_schedules()
                for s: rs
                    if s[schedule.id] == id
                        for z: api.settings.zones.keys()
                            if s.is_set(schedule.zones, z)
                                api.settings.zones[z].set_target_temp(target)
                                api.settings.zones.set_relay(z)
                                api.settings.zones.pub_heat(z)
                            end
                        end
                    end
                end
            end
        end
        # If there are other fields, update schedule as normal
        if api.settings.schedules.update(payload) util.config.restart() end    
    end
    def delete(idx)
        if api.settings.schedules.pop(idx) util.config.restart() end
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
        # Restore configuration options
        util.config.configure_options()
        # Create the override capability
        util.override = override()
        # Create the scheduler capability
        util.scheduler = scheduler()
        # Create a tasmota driver
        util.driver = driver()
        # Register the tasmota driver
        api.add_driver(util.driver)
        # Register commands
        running_command()
        zone_command()
        zones_command()
        schedule_command()
        schedules_command()
        options_command()
        modes_command()
        days_command()
        labels_command()
        # Fires when RTC has initialized (deferred)
        api.add_rule('Time#Initialized', /-> 
            api.set_timer(0, /-> self.time_initialized())
        )
        # Fires when MQTT has connected
        api.add_rule('Mqtt#Connected', /-> self.mqtt_connected())
        # If ACK received from display, flag as initialised
        api.add_rule("HeatingDisplay=ACK", /-> 
            api.set_timer(0, /-> self.display_initialised())
        )       
        # If ACK received from UI, flag as initialised
        api.add_rule("HeatingUI=ACK", /-> 
            api.set_timer(0, /-> self.ui_initialised())
        )
        # Request ACK frm UI & DISPLAY modules
        ui.publish("SYN")
        disp.publish("SYN")
        # Register button press triggers
        util.buttons = buttons()
        # If Alexa emulation enabled configure Alexa devices
        if api.cmd("Emulation")['Emulation'] == 2
            util.alexa = alexa(api.settings.zones)
        end
    end
    # Called once the RTC is initialized (Time#Initialized)
    def time_initialized()
        # Start the scheduler
        util.scheduler.start()
        # Hydrate schedules and zone overrides
        util.config.refresh()
    end
    # When MQTT connects send heating status for all zones
    def mqtt_connected()
        if util.config.is_option_set(util.options['MQTT'])
            for z: 0 .. size(api.settings.zones)-1
                api.settings.zones.get_status(z).pub_mqtt()
            end
        end
    end
    def display_initialised()
        api.set_timer(0, /->api.remove_rule("HeatingDisplay=ACK"))
        api.set_timer(0, /->api.remove_rule("HeatingDisplay=SYN"))
        var opt = util.options['DISPLAY']
        util.config.configure_option(opt, util.config.is_option_set(opt))
    end
    def ui_initialised()
        ui.initialised = true
        api.set_timer(0, /->api.remove_rule("HeatingUI=ACK"))
        api.set_timer(0, /->api.remove_rule("HeatingUI=SYN"))
        var opt = util.options['UI']
        util.config.configure_option(opt, util.config.is_option_set(opt))
    end
end

heating.controller = HeatingController
return heating
