#  ------------------------------------------------------------------------------------------------------
#  lvgl_display.be - Berry scripting language
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

var lvgl_display = module('lvgl_display')

class wifi
    # Is wifi connected?
    static connected = false
    # Used to hold wifi notification callback
    static callback = nil
    # Notify consumer of wifi status changes
    static def set_status(bool)
        wifi.connected = bool
        if wifi.callback
            wifi.callback(wifi.connected)
        end
    end
 end

 class clock
    static callback = nil
    static initialised = false
    static waiting = false
    static def initialise()
        clock.initialised = true
        if clock.waiting
            clock.waiting = false
            clock.callback()
            clock.set_timer()
        end
    end
    static def start(callback)
        clock.callback = callback
        if clock.initialised
            clock.set_timer()
        else
            clock.waiting = true
        end
    end
    static def set_timer()
        tasmota.set_timer(
            def()
                var l = tasmota.rtc()['local']
                var t = tasmota.time_dump(l)
                return 60000-t['sec']*1000
            end(),
            def() 
                if clock.callback
                    clock.callback()
                end
                clock.set_timer() 
            end, 
            "hc_lvgl_timer"
        )
    end
    static def stop()
        tasmota.remove_timer("hc_lvgl_timer")
    end
 end

class touchscreen
    # keep static references for styles
    static gs, bs, zs, ns, ms
    var modes
    # Grid memnbers
    var grid
    var col_dsc
    var row_dsc
    # Banner members
    var banner
    var font20 
    var datetime 
    var wifi_icon
    # Panel members
    var panels
    var colors 
    var modes_str
    var zones
    # Constructor
    def init()
        lv.start()
        self.modes = tasmota.cmd("HeatingModes")['HeatingModes']
        self.modes_str = self.modes.concat('\n')
        self.font20 = lv.montserrat_font(20)
        self.panels = []
        self.colors = [
            lv.PALETTE_BLUE, 
            lv.PALETTE_GREEN, 
            lv.PALETTE_RED
        ]
        self.zones = {}
    end
    def switch_clicked_cb(obj, event)
        var code = event.code
        if code == lv.EVENT_VALUE_CHANGED
            var zone = int(event.user_data)
            var power = obj.has_state(lv.STATE_CHECKED)
            tasmota.cmd(string.format("HeatingZone%s %s", zone+1, power))
        end
    end
    def dropdown_changed_cb(obj, event)
        var code = event.code
        if code == lv.EVENT_VALUE_CHANGED
            var zone = int(event.user_data)
            var option = obj.get_selected()
            var payload = {"update": {"mode": option}}
            if option == 1 payload["update"]['hours'] = 1 end
            tasmota.cmd(string.format("HeatingZone%s %s", zone+1, json.dump(payload)))
        end
    end
    def update_clock()
        self.datetime.set_text(tasmota.strftime("%d %b %Y %H:%M", tasmota.rtc()['local']))
    end
    def wifi_connected(bool)
        self.wifi_icon.set_style_text_color(
            lv.palette_main(bool ? lv.PALETTE_BLUE : lv.PALETTE_RED), 0
        )
    end
    def set_styles()
        # Main container style
        if touchscreen.gs != nil return end
        touchscreen.gs = lv.style()
        touchscreen.gs.set_bg_color(lv.color_black(),0)
        touchscreen.gs.set_bg_grad_color(lv.palette_main(lv.PALETTE_ORANGE), 0)
        touchscreen.gs.set_bg_grad_dir(lv.GRAD_DIR_VER, 0)
        touchscreen.gs.set_radius(0)
        touchscreen.gs.set_border_width(0)
        touchscreen.gs.set_pad_top(0)
        touchscreen.gs.set_pad_bottom(10)
        # Top banner style
        if touchscreen.bs != nil return end
        touchscreen.bs = lv.style()
        touchscreen.bs.set_text_font(self.font20)
        touchscreen.bs.set_border_side(lv.BORDER_SIDE_BOTTOM)
        touchscreen.bs.set_bg_opa(lv.OPA_TRANSP)
        touchscreen.bs.set_border_width(1)
        touchscreen.bs.set_border_color(lv.palette_main(lv.PALETTE_ORANGE))
        touchscreen.bs.set_text_color(lv.palette_main(lv.PALETTE_GREY))
        touchscreen.bs.set_pad_left(0)
        touchscreen.bs.set_pad_right(0)
        touchscreen.bs.set_pad_top(12)
        touchscreen.bs.set_pad_bottom(0)
        # Zone panel style
        if touchscreen.zs != nil return end
        touchscreen.zs = lv.style()
        touchscreen.zs.set_radius(15)
        touchscreen.zs.set_border_width(0)
        touchscreen.zs.set_pad_left(0)
        touchscreen.zs.set_pad_right(0)
        touchscreen.zs.set_pad_row(7)
        # if resolution is 480x320 increase font size
        if lv.get_hor_res() == 480
            touchscreen.zs.set_text_font(self.font20)
        end
        # Heating zone name style
        if touchscreen.ns != nil return end
        touchscreen.ns = lv.style()
        touchscreen.ns.set_bg_opa(lv.OPA_COVER)
        touchscreen.ns.set_radius(15)
        touchscreen.ns.set_pad_left(5)
        touchscreen.ns.set_pad_right(5)
        touchscreen.ns.set_pad_top(3)
        touchscreen.ns.set_pad_bottom(3)
        touchscreen.ns.set_bg_color(lv.palette_main(lv.PALETTE_GREY))
        touchscreen.ns.set_text_color(lv.color_white())
        # Heating zone mode style
        if touchscreen.ms != nil return end
        touchscreen.ms = lv.style()
        touchscreen.ms.set_bg_opa(lv.OPA_TRANSP)
        touchscreen.ms.set_pad_left(0)
        touchscreen.ms.set_pad_right(0)
        touchscreen.ms.set_pad_top(0)
        touchscreen.ms.set_pad_bottom(0)
        touchscreen.ms.set_width(60)
        touchscreen.ms.set_border_width(0)
    end
    def set_grid()
        # Resize the panels to fit different screen resolutions
        var fr = lv.grid_fr(10)
        self.col_dsc = lv.coord_arr([fr, fr, fr, lv.GRID_TEMPLATE_LAST])
        self.row_dsc = lv.coord_arr([40, fr, lv.GRID_TEMPLATE_LAST])
        self.grid = lv.obj(lv.scr_act())
        self.grid.set_grid_align(lv.GRID_ALIGN_SPACE_BETWEEN, lv.GRID_ALIGN_SPACE_BETWEEN)
        self.grid.set_grid_dsc_array(self.col_dsc, self.row_dsc)
        self.grid.set_size(lv.get_hor_res(), lv.get_ver_res())
        self.grid.center()
        self.grid.add_style(touchscreen.gs, 0)
    end
    def set_banner()
        # Create the banner container - which is a line
        self.banner = lv.line(self.grid)
        self.banner.add_style(touchscreen.bs, 0)
        self.banner.set_grid_cell(lv.GRID_ALIGN_STRETCH, 0, 3, lv.GRID_ALIGN_STRETCH, 0, 1)
        # Create the banner labels and widgets
        self.datetime = lv.label(self.banner)
        self.datetime.set_align(lv.ALIGN_CENTER)
        self.datetime.set_text("Starting...")
        self.wifi_icon = lv.label(self.banner)
        self.wifi_icon.set_align(lv.ALIGN_RIGHT_MID)
        self.wifi_icon.set_text(lv.SYMBOL_WIFI)
        var color = wifi.connected ? lv.PALETTE_BLUE : lv.PALETTE_RED 
        self.wifi_icon.set_style_text_color(lv.palette_main(color), 0)
        # subscribe to wifi notifications
        wifi.callback = / bool -> self.wifi_connected(bool)
        # subscribe to initial time
        if clock.initialised 
            self.update_clock()
            clock.start(self.update_clock)
        else
            clock.callback = / -> self.update_clock()
        end
    end
    def set_panels()
        for z: 0 .. 2
            var p = lv.obj(self.grid)
            p.add_style(touchscreen.zs, 0)
            p.set_style_bg_color(lv.palette_lighten(self.colors[z], 3), 0)
            p.set_flex_flow(lv.FLEX_FLOW_COLUMN)
            p.set_flex_align(lv.FLEX_ALIGN_START, lv.FLEX_ALIGN_CENTER, lv.FLEX_ALIGN_CENTER)
            p.set_grid_cell(lv.GRID_ALIGN_STRETCH, z, 1, lv.GRID_ALIGN_STRETCH, 1, 1)
            p.set_scrollbar_mode(0)
            self.panels.push(p)
        end
    end
    def set_zone(z)
        self.zones[z] = {}
        self.zones[z]['label'] = lv.label(self.panels[z])
        self.zones[z]['label'].add_style(touchscreen.ns, 0)
        self.zones[z]['mode'] = lv.dropdown(self.panels[z])
        self.zones[z]['mode'].set_symbol(nil)
        self.zones[z]['mode'].set_dir(z<2 ? lv.DIR_RIGHT : lv.DIR_LEFT)
        self.zones[z]['mode'].add_style(touchscreen.ms, 0)
        self.zones[z]['mode'].set_options_static(self.modes_str)
        self.zones[z]['mode'].add_event_cb(
            / o,e -> self.dropdown_changed_cb(o, e), 
            lv.EVENT_VALUE_CHANGED, 
            z
        )
        self.zones[z]['power'] = lv.label(self.panels[z])
        self.zones[z]['until'] = lv.label(self.panels[z])
        self.zones[z]['expiry'] = lv.label(self.panels[z])
        self.zones[z]['switch'] = lv.switch(self.panels[z])
        self.zones[z]['switch'].set_style_bg_color(lv.palette_main(self.colors[2]), 0)
        self.zones[z]['switch'].add_event_cb(
            / o,e -> self.switch_clicked_cb(o, e), 
            lv.EVENT_VALUE_CHANGED, 
            z
        )
    end
    def clear_zone(zone)
        if zone > 3 return end 
        self.panels[zone-1].clean()
        self.zones.remove(zone-1)
    end
    def update_zone(zone)
        var idx = zone['id']-1
        if idx > 2 return end
        if !self.zones.contains(idx) self.set_zone(idx) end
        self.zones[idx]['label'].set_text(zone['label'])
        self.zones[idx]['mode'].set_selected(zone['mode'])
        var const = 12&(1<<zone['mode'])
        var color = zone['power'] ? self.colors[0] : self.colors[2]
        var expiry = tasmota.strftime("%a %R", zone['expiry'])
        self.zones[idx]['power'].set_text(const ? 'CONST' : zone['power'] ? 'ON' : 'OFF')
        self.zones[idx]['power'].set_style_text_color(lv.palette_darken(color, 1), 0)
        self.zones[idx]['until'].set_text(const ? '' : 'Until')
        self.zones[idx]['expiry'].set_text(const ? '' : expiry)
        if zone['power']
            self.zones[idx]['switch'].add_state(lv.STATE_CHECKED)
        else
            self.zones[idx]['switch'].clear_state(lv.STATE_CHECKED)
        end
    end
    def start()
        self.power(true)
        self.set_styles()
        self.set_grid()
        self.set_banner()
        self.set_panels()
        self.start_clock()
        tasmota.add_rule("HeatingDisplay#HeatingZone", /z-> self.update_zone(z))
        tasmota.add_rule("HeatingDisplay#ClearZone", /z-> self.clear_zone(z))
    end
    def start_clock()
        clock.start(/->self.update_clock())
    end
    def stop_clock()
        clock.stop()
    end
    def stop()
        lv.scr_load(lv.obj(0))
        wifi.callback = nil
        tasmota.remove_rule("HeatingDisplay#HeatingZone")
        tasmota.remove_rule("HeatingDisplay#ClearZone")
        self.stop_clock()
        self.grid.del()
        self.power(false)
    end
    def power(bool)
        import display
        display.dimmer(bool ? 100 : 0)
    end
end

lvgl_display._display = nil 

def ack()
    tasmota.publish_result('{"HeatingDisplay":"ACK"}', 'RESULT')
end

def start()
    if lvgl_display._display return end
    lvgl_display._display = touchscreen()
    lvgl_display._display.start()
end
def stop()
    if !lvgl_display._display return end
    lvgl_display._display.stop()
    lvgl_display._display = nil
end

# Subscibe to Tasmota events
tasmota.add_rule("Wifi#Connected", /-> wifi.set_status(true))
tasmota.add_rule("Wifi#Disconnected", /-> wifi.set_status(false))
tasmota.add_rule("Time#Initialized", /-> clock.initialise())
# Subscribe to events sent from Heating Controller
tasmota.add_rule("HeatingDisplay==ON", /->tasmota.set_timer(0, /->start()))
tasmota.add_rule("HeatingDisplay==OFF", /->tasmota.set_timer(0, /->stop()))
tasmota.add_rule("HeatingDisplay==SYN", /->tasmota.set_timer(0, /->ack()))
# Once lvgl_display loads an initialisation trigger is broadcast
ack()

return lvgl_display

