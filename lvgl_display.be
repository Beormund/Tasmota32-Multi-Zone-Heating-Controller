var lvgl_display = module('lvgl_display')

lv.start()

class touchscreen
    var util, zone_count
    # The screen members
    var screen
    # The style members
    var heating_style, banner_style, zone_style, name_style, mode_style
    # The grid memnbers
    var grid
    # The banner members
    var banner, font20, datetime, wifi_icon
    # The panel members
    var panels, colors, modes_str, zones
    # Constructor
    def init(util, zone_count)
        self.zone_count = zone_count && zone_count > 3 ? 3 : zone_count
        self.util = util
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
            self.util.commands['zone'].cmd_set_power(zone, power)
        end
    end
    def dropdown_changed_cb(obj, event)
        var code = event.code
        if code == lv.EVENT_VALUE_CHANGED
            var zone = int(event.user_data)
            var option = obj.get_selected()
            var payload = {"mode": option, "hours": 1}
            self.util.commands['zone'].cmd_set_mode(zone, payload)
        end
    end
    def wifi_connected(bool)
        self.wifi_icon.set_style_text_color(
            lv.palette_main(bool ? lv.PALETTE_BLUE : lv.PALETTE_RED), 0
        )
    end
    def set_screen()
        self.screen = lv.scr_act()
        self.screen.set_style_bg_color(lv.color_white(), 0)
        self.screen.set_style_bg_grad_color(lv.palette_main(lv.PALETTE_GREY), 0)
        self.screen.set_style_bg_grad_dir(lv.GRAD_DIR_VER, 0)
    end
    def set_styles()
        # Main container style
        self.heating_style = lv.style()
        self.heating_style.set_bg_opa(0)
        self.heating_style.set_border_width(0)
        self.heating_style.set_pad_top(0)
        self.heating_style.set_pad_bottom(10)
        # Top banner style
        self.banner_style = lv.style()
        self.banner_style.set_text_font(self.font20)
        self.banner_style.set_border_side(lv.BORDER_SIDE_BOTTOM)
        self.banner_style.set_bg_opa(lv.OPA_TRANSP)
        self.banner_style.set_border_width(1)
        self.banner_style.set_border_color(lv.palette_main(lv.PALETTE_GREY))
        self.banner_style.set_text_color(lv.palette_darken(lv.PALETTE_GREY, 1))
        self.banner_style.set_pad_left(0)
        self.banner_style.set_pad_right(0)
        self.banner_style.set_pad_top(12)
        self.banner_style.set_pad_bottom(0)
        # Zone panel style
        self.zone_style = lv.style()
        self.zone_style.set_radius(15)
        self.zone_style.set_bg_opa(190)
        self.zone_style.set_border_width(0)
        self.zone_style.set_pad_left(0)
        self.zone_style.set_pad_right(0)
        self.zone_style.set_pad_row(7)
        # Heating zone name style
        self.name_style = lv.style()
        self.name_style.set_bg_opa(lv.OPA_COVER)
        self.name_style.set_radius(15)
        self.name_style.set_pad_left(5)
        self.name_style.set_pad_right(5)
        self.name_style.set_pad_top(3)
        self.name_style.set_pad_bottom(3)
        self.name_style.set_bg_color(lv.palette_main(lv.PALETTE_GREY))
        self.name_style.set_text_color(lv.color_white())
        # Heating zone mode style
        self.mode_style = lv.style()
        self.mode_style.set_bg_opa(lv.OPA_TRANSP)
        self.mode_style.set_pad_left(0)
        self.mode_style.set_pad_right(0)
        self.mode_style.set_pad_top(0)
        self.mode_style.set_pad_bottom(0)
        self.mode_style.set_width(60)
        self.mode_style.set_height(16)
        self.mode_style.set_border_width(0)
    end
    def set_grid()
        var col_dsc = lv.coord_arr([90, 90, 90, lv.GRID_TEMPLATE_LAST])
        var row_dsc = lv.coord_arr([40, 177, lv.GRID_TEMPLATE_LAST])
        self.grid = lv.obj(self.screen)
        self.grid.set_grid_align(lv.GRID_ALIGN_SPACE_BETWEEN, lv.GRID_ALIGN_SPACE_BETWEEN)
        self.grid.set_grid_dsc_array(col_dsc, row_dsc)
        self.grid.set_size(lv.get_hor_res(), lv.get_ver_res())
        self.grid.center()
        self.grid.add_style(self.heating_style, 0)
    end
    def set_banner()
        # Create the banner container - which is a line
        self.banner = lv.line(self.grid)
        self.banner.add_style(self.banner_style, 0)
        self.banner.set_grid_cell(lv.GRID_ALIGN_STRETCH, 0, 3, lv.GRID_ALIGN_STRETCH, 0, 1)
        # Create the banner labels and widgets
        self.datetime = lv.label(self.banner)
        self.datetime.set_align(lv.ALIGN_CENTER)
        self.datetime.set_text("Starting...")
        self.wifi_icon = lv.label(self.banner)
        self.wifi_icon.set_align(lv.ALIGN_RIGHT_MID)
        self.wifi_icon.set_text(lv.SYMBOL_WIFI)
        var color = self.util.wifi_connected ? lv.PALETTE_BLUE : lv.PALETTE_RED 
        self.wifi_icon.set_style_text_color(lv.palette_main(color), 0)
        # subscribe to wifi notifications
        self.util.add_wifi_cb(/ bool ->self.wifi_connected(bool), 'wifi')
    end
    def set_panels()
        for z: 0 .. 2
            var p = lv.obj(self.grid)
            p.add_style(self.zone_style, 0)
            p.set_style_bg_color(lv.palette_lighten(self.colors[z], 3), 0)
            p.set_flex_flow(lv.FLEX_FLOW_COLUMN)
            p.set_flex_align(lv.FLEX_ALIGN_START, lv.FLEX_ALIGN_CENTER, lv.FLEX_ALIGN_CENTER)
            p.set_grid_cell(lv.GRID_ALIGN_STRETCH, z, 1, lv.GRID_ALIGN_STRETCH, 1, 1)
            self.panels.push(p)
        end
    end
    def set_zone(z)
        self.zones[z] = {}
        self.zones[z]['label'] = lv.label(self.panels[z])
        self.zones[z]['label'].add_style(self.name_style, 0)
        self.zones[z]['mode'] = lv.dropdown(self.panels[z])
        self.zones[z]['mode'].set_symbol(nil)
        self.zones[z]['mode'].set_dir(z<2 ? lv.DIR_RIGHT : lv.DIR_LEFT)
        self.zones[z]['mode'].add_style(self.mode_style, 0)
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
            lv.EVENT_ALL, 
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
        self.set_screen()
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
        self.util.remove_wifi_cb('wifi')
        self.screen.del()
    end
    def power(bool)
        var disp = tasmota.get_power().size()
        tasmota.set_power(disp-1, bool)
    end
end

lvgl_display.screen = touchscreen
return lvgl_display

