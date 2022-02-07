var lvgl_display = module('lvgl_display')

lv.start()

# keep a global reference as berry allocates
# memory as immortal for lvgl styles. This
# avoids memory leaks.
var gs, bs, zs, ns, ms

class touchscreen
    # Constructor members
    var util
    var wifi
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
    def init(util, wifi)
        self.util = util
        self.wifi = wifi
        self.modes_str = util.modes.concat('\n')
        self.font20 = lv.montserrat_font(20)
        self.panels = []
        self.colors = [
            lv.PALETTE_BLUE, 
            lv.PALETTE_GREEN, 
            lv.PALETTE_RED
        ]
        self.zones = {}
        self.start()
    end
    def switch_clicked_cb(obj, event)
        var code = event.code
        if code == lv.EVENT_VALUE_CHANGED
            var zone = int(event.user_data)
            var power = obj.has_state(lv.STATE_CHECKED)
            tasmota.cmd(string.format("zone%s %s", zone+1, power))
        end
    end
    def dropdown_changed_cb(obj, event)
        var code = event.code
        if code == lv.EVENT_VALUE_CHANGED
            var zone = int(event.user_data)
            var option = obj.get_selected()
            var payload = {"update": {"mode": option}}
            if option == 1 payload["update"]['hours'] = 1 end
            tasmota.cmd(string.format("zone%s %s", zone+1, json.dump(payload)))
        end
    end
    def wifi_connected(bool)
        self.wifi_icon.set_style_text_color(
            lv.palette_main(bool ? lv.PALETTE_BLUE : lv.PALETTE_RED), 0
        )
    end
    def set_styles()
        # Main container style
        if gs != nil return end
        gs = lv.style()
        gs.set_bg_color(lv.color_black(),0)
        gs.set_bg_grad_color(lv.palette_main(lv.PALETTE_ORANGE), 0)
        gs.set_bg_grad_dir(lv.GRAD_DIR_VER, 0)
        gs.set_radius(0)
        gs.set_border_width(0)
        gs.set_pad_top(0)
        gs.set_pad_bottom(10)
        # Top banner style
        if bs != nil return end
        bs = lv.style()
        bs.set_text_font(self.font20)
        bs.set_border_side(lv.BORDER_SIDE_BOTTOM)
        bs.set_bg_opa(lv.OPA_TRANSP)
        bs.set_border_width(1)
        bs.set_border_color(lv.palette_main(lv.PALETTE_ORANGE))
        bs.set_text_color(lv.palette_main(lv.PALETTE_GREY))
        bs.set_pad_left(0)
        bs.set_pad_right(0)
        bs.set_pad_top(12)
        bs.set_pad_bottom(0)
        # Zone panel style
        if zs != nil return end
        zs = lv.style()
        zs.set_radius(15)
        zs.set_border_width(0)
        zs.set_pad_left(0)
        zs.set_pad_right(0)
        zs.set_pad_row(7)
        # if resolution is 480x320 increase font size
        if lv.get_hor_res() == 480
            zs.set_text_font(self.font20)
        end
        # Heating zone name style
        if ns != nil return end
        ns = lv.style()
        ns.set_bg_opa(lv.OPA_COVER)
        ns.set_radius(15)
        ns.set_pad_left(5)
        ns.set_pad_right(5)
        ns.set_pad_top(3)
        ns.set_pad_bottom(3)
        ns.set_bg_color(lv.palette_main(lv.PALETTE_GREY))
        ns.set_text_color(lv.color_white())
        # Heating zone mode style
        if ms != nil return end
        ms = lv.style()
        ms.set_bg_opa(lv.OPA_TRANSP)
        ms.set_pad_left(0)
        ms.set_pad_right(0)
        ms.set_pad_top(0)
        ms.set_pad_bottom(0)
        ms.set_width(60)
        ms.set_border_width(0)
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
        self.grid.add_style(gs, 0)
    end
    def set_banner()
        # Create the banner container - which is a line
        self.banner = lv.line(self.grid)
        self.banner.add_style(bs, 0)
        self.banner.set_grid_cell(lv.GRID_ALIGN_STRETCH, 0, 3, lv.GRID_ALIGN_STRETCH, 0, 1)
        # Create the banner labels and widgets
        self.datetime = lv.label(self.banner)
        self.datetime.set_align(lv.ALIGN_CENTER)
        self.datetime.set_text("Starting...")
        self.wifi_icon = lv.label(self.banner)
        self.wifi_icon.set_align(lv.ALIGN_RIGHT_MID)
        self.wifi_icon.set_text(lv.SYMBOL_WIFI)
        var color = self.wifi.connected ? lv.PALETTE_BLUE : lv.PALETTE_RED 
        self.wifi_icon.set_style_text_color(lv.palette_main(color), 0)
        # subscribe to wifi notifications
        self.wifi.add_cb(/ c ->self.wifi_connected(c), 'wifi')
    end
    def set_panels()
        for z: 0 .. 2
            var p = lv.obj(self.grid)
            p.add_style(zs, 0)
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
        self.zones[z]['label'].add_style(ns, 0)
        self.zones[z]['mode'] = lv.dropdown(self.panels[z])
        self.zones[z]['mode'].set_symbol(nil)
        self.zones[z]['mode'].set_dir(z<2 ? lv.DIR_RIGHT : lv.DIR_LEFT)
        self.zones[z]['mode'].add_style(ms, 0)
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
        if zone > 2 return end 
        self.panels[zone].clean()
        self.zones.remove(zone)
    end
    def update_zone(status)
        var zone = status.zone
        if zone > 2 return end
        if !self.zones.contains(zone) self.set_zone(zone) end
        self.zones[zone]['label'].set_text(status.label)
        self.zones[zone]['mode'].set_selected(status.mode)
        var const = 12&(1<<status.mode)
        var color = status.power ? self.colors[0] : self.colors[2]
        var expiry = status.format(["%%a %%R"])
        self.zones[zone]['power'].set_text(const ? 'CONST' : status.state)
        self.zones[zone]['power'].set_style_text_color(lv.palette_darken(color, 1), 0)
        self.zones[zone]['until'].set_text(const ? '' : 'Until')
        self.zones[zone]['expiry'].set_text(const ? '' : expiry)
        if status.power
            self.zones[zone]['switch'].add_state(lv.STATE_CHECKED)
        else
            self.zones[zone]['switch'].clear_state(lv.STATE_CHECKED)
        end
    end
    def start()
        self.power(true)
        self.set_styles()
        self.set_grid()
        self.set_banner()
        self.set_panels()
    end
    def update_clock(formatter)
        self.datetime.set_text(formatter("%d %b %Y %H:%M"))
    end
    def start_clock()
        var callback = / formatter -> self.update_clock(formatter)
        var millis = / now -> 60000-now['sec']*1000
        self.util.set_time(callback)
        self.util.set_timer(millis, callback, 'lvgl_ticker', true)
    end
    def stop_clock()
        self.util.remove_timer('lvgl_ticker')
    end
    def clear()
        lv.scr_load(lv.obj(0))
        self.wifi.remove_cb('wifi')
        self.grid.del()
        self.power(false)
    end
    def power(bool)
        import display
        display.dimmer(bool ? 100 : 0)
    end
end

lvgl_display.screen = touchscreen
return lvgl_display

