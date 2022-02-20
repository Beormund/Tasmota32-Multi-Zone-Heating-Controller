import webserver
import string
import json

var heating_ui = module('heating_ui')

# Display Schedule Summary/Editor in 'Configure Heating'
class schedule_ui
    # Get list of day indices
    # [0,1,1,1,1,1,0] -> [-MTWT--]
    def flags2days(days, flags)
        var l = []
        for d: days.keys()
            var dl = days[d][0]
            l.push(flags[d] ? dl : string.format("<mark>%s</mark>", dl))
        end
        return l.concat()
    end
    # Send a list of schedules as HTML fragment
    def show_schedules(html, days, schedules, labels)
        webserver.content_send(html[0])
        for s: schedules
            var ds = self.flags2days(days, s['days'])
            var l = []
            for z: s['zones'].keys()
                if s['zones'][z] l.push(labels[z]) end
            end
            var zs = l.concat(' ')
            webserver.content_send(
                string.format(
                    html[1], s['id'], s['id'], s['on'], s['off'], ds, zs, 
                    size(zs) > 10 ? zs[0 .. 11] + ".." : zs
                )
            )
        end
        var new_id = schedules.size()+1
        webserver.content_send(string.format(html[2], new_id ))
    end
    # Displays a web control for editing a single schedule
    def show_editor(id, html, days, s, labels)
        var action = s ? 'update' : 'new'
        var _zones = []
        for i: 1 .. size(labels) _zones.push(0) end
        s = s ? s : {"on": "00:00", "off": "00:00", "days": [0,0,0,0,0,0,0], "zones": _zones, "target temp": nil}
        webserver.content_send(html[0])
        webserver.content_send(string.format(html[1], id))
        var target = s['target temp'] != nil ? s['target temp'] : ''
        webserver.content_send(string.format(html[2], id, s['on'], s['off'], target))
        webserver.content_send(html[3])
        for d: 0 .. size(days)-1
            var checked = s['days'][d] ? 'checked' : ''
            var dl = days[d]
            webserver.content_send(string.format(html[4], dl, d, checked, dl, dl))
        end
        webserver.content_send(html[5])
        for z: 0 .. size(labels)-1
            var checked = s['zones'][z] ? 'checked' : ''
            var zl = labels[z]
            webserver.content_send(string.format(html[6], zl, z, checked, zl, zl))
        end
        webserver.content_send(string.format(html[7], action, id))
        if action == 'update'
            webserver.content_send(html[8])
        end
        webserver.content_send(html[9])
    end
end

# Displays zone sumarry/editor widgets in 'Configure Heating'
class zone_ui
    # Shows a list of zones with status info
    def show_zones(html, zones)
        webserver.content_send(html[0])
        for z: 0 .. size(zones)-1
            webserver.content_send(string.format(html[1], z+1, z+1, zones[z]['info']))
        end
        webserver.content_send(string.format(html[2], zones.size()+1))
        webserver.content_send(html[3])
    end
    # Displays a web control for editing a single zone
    def show_editor(zid, html, z)
        var modes = tasmota.cmd('HeatingModes')['HeatingModes']
        var action = z != nil ? 'update' : 'new'
        z = z ? z : {'label': 'ZN' .. zid, 'mode': 0, 'target temp': nil}
        var target = z['target temp'] != nil ? z['target temp'] : ''
        webserver.content_send(html[0])
        webserver.content_send(string.format(html[1], zid, zid))
        webserver.content_send(string.format(html[2], z['label'], target))
        for k: 0 .. size(modes)-1
            var mode = modes[k]
            var checked = z['mode'] == k ? 'checked' : ''
            webserver.content_send(string.format(html[3], mode, k, checked, mode, mode))
        end
        webserver.content_send(html[4])
        webserver.content_send(string.format(html[5], action))
        if action == 'update'
            webserver.content_send(html[6])
        end
        webserver.content_send(html[7])
    end
end

# Displays options in 'Configure Heating'
class options_ui
    def show_options(html)
        webserver.content_send(html[0])
        var options = tasmota.cmd("HeatingOptions")['HeatingOptions']
        for k: options.keys()
            var checked = options[k] ? 'checked' : ''
            webserver.content_send(string.format(html[1], k, checked, k, k))
        end
        webserver.content_send(html[2])
    end
end

class http_manager
    # Updates a zone based on web form entry
    def update_zone(id)
        if webserver.has_arg('delete')
            tasmota.cmd(string.format("HeatingZone%d delete", id))
            return
        end
        if webserver.has_arg('new') || webserver.has_arg('update')
            var zone = {}
            # Process label
            if webserver.has_arg('label')
                zone['label'] = webserver.arg('label')
            end
            # Process mode
            if webserver.has_arg('modes[]')
                zone['mode'] = int(webserver.arg('modes[]'))
            end
            # Process hours
            if zone['mode'] == 1 && webserver.has_arg('hours[]')
                zone['hours'] = int(webserver.arg('hours[]'))
            end
            # Process target temp
            if webserver.has_arg('t')
                var t = webserver.arg('t')
                if t == ''
                    zone['target'] = nil
                elif number(t) != 0
                    zone['target'] = number(t)
                end
            end
            if webserver.has_arg('new') 
                tasmota.cmd(string.format("HeatingZone %s", json.dump({"new": zone})))
            else
                tasmota.cmd(string.format("HeatingZone%d %s", id, json.dump({"update": zone})))
            end
        end
    end
    # Deletes/Updates/Creates a schedule based on web form entry
    def update_schedule(id)
        # Hydrate a schedule object for a new/update action
        def tosched()
            var labels = tasmota.cmd("HeatingLabels")['HeatingLabels']
            var zones = []
            for i: 1 .. size(labels) zones.push(0) end
            var s = {'days': [0,0,0,0,0,0,0], 'zones': zones}
            for arg: 0 .. webserver.arg_size()-1
                # Avoid any garbage args present
                var name = webserver.arg_name(arg)
                var value = webserver.arg(arg)
                # Process days
                if name == 'days[]'
                    s['days'].setitem(int(value), 1)
                # Process zones
                elif name == 'zones[]'
                    s['zones'].setitem(int(value), 1) 
                # Process on/off times
                elif name == 'on'
                    s['on'] = value
                elif name == 'off'
                    s['off'] = value
                elif name == 't'
                    var t = webserver.arg('t')
                    if t == ''
                        s['target'] = nil
                    elif number(t) != 0
                        s['target'] = number(t)
                    end
                end 
            end
            return s         
        end        
        if webserver.has_arg('delete')
            tasmota.cmd(string.format('HeatingSchedule%d delete', id))
        elif webserver.has_arg('update')
            var payload = json.dump({"update": tosched(id)})
            tasmota.cmd(string.format("HeatingSchedule%d %s", id, payload))
        elif webserver.has_arg('new')
            var payload = json.dump({"new": tosched(id)})
            tasmota.cmd(string.format("HeatingSchedule %s", payload))
        end
    end
    # Updates options
    def update_options()
        var options = tasmota.cmd("HeatingOptions")['HeatingOptions']
        var payload = {}
        for k: options.keys()
            payload[k] = webserver.has_arg(k)
        end
        tasmota.cmd("HeatingOptions " .. json.dump(payload))
    end
    #  Determines which widgets are displayed
    def on_http_get(html)
        if !webserver.check_privileged_access() return nil end
        webserver.content_start('Configure Heating')
        webserver.content_send_style()
        if webserver.has_arg('id')
            var sid = int(webserver.arg('id'))
            var days = tasmota.cmd("HeatingDays")['HeatingDays']
            var schedules = tasmota.cmd("HeatingSchedules")['HeatingSchedules']
            var schedule = sid <= size(schedules) ? schedules[sid-1] : nil
            var labels = tasmota.cmd("HeatingLabels")['HeatingLabels']
            var gui = schedule_ui()
            gui.show_schedules(html['sched-sum'], days, schedules, labels)
            gui.show_editor(sid, html['sched'], days, schedule, labels)
        elif webserver.has_arg('zid')
            var zid = int(webserver.arg('zid'))
            var zones = tasmota.cmd("HeatingZones")['HeatingZones']
            var zone = zid <= size(zones) ? zones[zid-1] : nil
            var gui = zone_ui()
            gui.show_zones(html['zone-sum'], zones)
            gui.show_editor(zid, html['zone'], zone)
        else
            var days = tasmota.cmd("HeatingDays")['HeatingDays']
            var schedules = tasmota.cmd("HeatingSchedules")['HeatingSchedules']
            var zones = tasmota.cmd("HeatingZones")['HeatingZones']
            var labels = []
            for z: 0 .. size(zones)-1 labels.push(zones[z]['label']) end
            zone_ui().show_zones(html['zone-sum'], zones)
            schedule_ui().show_schedules(html['sched-sum'], days, schedules, labels)
            options_ui().show_options(html['options'])
        end
        webserver.content_button(webserver.BUTTON_CONFIGURATION)
        webserver.content_stop()
    end
    # Handles data submitted by web widgets
    def on_http_post()
        if webserver.has_arg('z')
            self.update_zone(int(webserver.arg('z')))
        elif webserver.has_arg('s') 
            self.update_schedule(int(webserver.arg('s')))
        elif webserver.has_arg('o')
            self.update_options()
        end
    end
end

heating_ui.wd = ''

class driver
    var _button, _enabled
    def init()
        self._enabled = false
        # Subscribe to events sent from Heating Controller
        tasmota.add_rule("HeatingUI==ON", /->tasmota.set_timer(0, /->self.start()))
        tasmota.add_rule("HeatingUI==OFF", /->self.stop())
        tasmota.add_rule("HeatingUI==SYN", /->tasmota.set_timer(0, /->self.ack()))
        # Once UI loads an initialisation trigger is broadcast
        self.ack()          
    end
    # Used to load HTML for Configure Heating UI
    def load_file(fn)
        var obj, f
        f = open(heating_ui.wd .. fn, 'r')
        obj = json.load(f.read())
        f.close()
        return obj
    end        
    # Displays a "Configure Heating" button on the configuration page
    def web_add_config_button()
        if !self._button
            self._button = self.load_file('html.json')['button']
        end
        webserver.content_send(self._button)
    end
    # Add HTTP POST and GET handlers
    def web_add_handler()
        webserver.on('/hm', / -> self.http_get(), webserver.HTTP_GET)
        webserver.on('/hm', / -> self.http_post(), webserver.HTTP_POST)
    end
    def http_get()
        if !self._enabled self.linkhome() end 
        var html = self.load_file('html.json')
        http_manager().on_http_get(html)
    end
    def http_post()
        if !self._enabled self.linkhome() end
        http_manager().on_http_post()
        self.http_get()
    end
    def linkhome()
        webserver.content_start('Configure Heating')
        webserver.content_send_style()
        webserver.content_send(self.load_file('html.json')['help'])
        webserver.content_button(webserver.BUTTON_CONFIGURATION)
        webserver.content_stop()
    end
    def start()
        if !self._enabled
            tasmota.add_driver(self)
            self.web_add_handler()
            self._enabled = true
        end
    end
    def stop()
        if self._enabled
            tasmota.remove_driver(self)
            self._enabled = false
        end
    end
    def ack()
        tasmota.publish_result('{"HeatingUI":"ACK"}', 'RESULT')
    end
end

# Create and hold a reference to the driver
var d = driver()

return heating_ui
















