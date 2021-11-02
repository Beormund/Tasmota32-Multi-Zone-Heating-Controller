#  ------------------------------------------------------------------------------------------------------
#  display.be - Berry scripting language
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


var display = module('display')

#  ------------------------------------------------------------------------------------
#  This is the driver for the Liquid Crystal LCD displays that use the I2C bus.
#  The backlight is on by default, since that is the most likely operating mode in
#  most cases. It is a direct berry port of the Arduino Liquid Crystal 12C C++ library.
#  Cols and Rows both start at 1, not zero.
#  -------------------------------------------------------------------------------------

class lcd_i2c

    # commands
    static LCD_CLEARDISPLAY = 0x01
    static LCD_RETURNHOME = 0x02
    static LCD_ENTRYMODESET = 0x04
    static LCD_DISPLAYCONTROL = 0x08
    static LCD_CURSORSHIFT = 0x10
    static LCD_FUNCTIONSET = 0x20
    static LCD_SETCGRAMADDR = 0x40
    static LCD_SETDDRAMADDR = 0x80

    # flags for display entry mode
    static LCD_ENTRYRIGHT = 0x00
    static LCD_ENTRYLEFT = 0x02
    static LCD_ENTRYSHIFTINCREMENT = 0x01
    static LCD_ENTRYSHIFTDECREMENT = 0x00

    # flags for display on/off control
    static LCD_DISPLAYON = 0x04
    static LCD_DISPLAYOFF = 0x00
    static LCD_CURSORON = 0x02
    static LCD_CURSOROFF = 0x00
    static LCD_BLINKON = 0x01
    static LCD_BLINKOFF = 0x00

    # flags for display/cursor shift
    static LCD_DISPLAYMOVE = 0x08
    static LCD_CURSORMOVE = 0x00
    static LCD_MOVERIGHT = 0x04
    static LCD_MOVELEFT = 0x00

    # flags for function set
    static LCD_8BITMODE = 0x10
    static LCD_4BITMODE = 0x00
    static LCD_2LINE = 0x08
    static LCD_1LINE = 0x00
    static LCD_5x10DOTS = 0x04
    static LCD_5x8DOTS = 0x00

    # flags for backlight control
    static LCD_BACKLIGHT = 0x08
    static LCD_NOBACKLIGHT = 0x00

    # Helper flags
    static LCD_LINES = {1: 0x80, 2: 0xC0, 3: 0x94, 4: 0xD4}
    static LCD_SLEEP = 1

    static Rg = 0x00    # Register default
    static En = 0x04    # Enable bit
    static Rs = 0x01    # Register select bit

    var address, wire, rows, cols, charsize, backlight, displaycontrol, displaymode

    #  Constructor
    #
    #  @param address    I2C slave address of the LCD display. Most likely printed on the
    #                    LCD circuit board, or look in the supplied LCD documentation.
    #  @param cols       Number of columns your LCD display has.
    #  @param rows       Number of rows your LCD display has.
    #  @param charsize   The size in dots that the display has, use LCD_5x10DOTS or LCD_5x8DOTS.
    def init(address, rows, cols, charsize)
        self.address = address ? address : 0x27
        self.rows = rows ? rows : 4
        self.cols = cols ? cols : 20
        self.charsize = self.LCD_5x8DOTS
        self.backlight = self.LCD_BACKLIGHT
        self.wire = tasmota.wire_scan(self.address)
        # Start the display
        self.begin()
    end
    def begin()
        # Set some defaults...
        var displayfunction = self.LCD_4BITMODE | self.LCD_1LINE | self.LCD_5x8DOTS
        if self.rows > 1
            displayfunction |= self.LCD_2LINE
        end
        # For some 1 line displays you can select a 10 pixel high font
        if self.charsize != 0 && self.rows == 1
            displayfunction |= self.LCD_5x10DOTS
        end
        # Reeset expanderand turn backlight off (Bit 8 =1)
        self.expand_write(self.backlight)
        tasmota.delay(1)
        # We start in 8bit mode, try to set 4 bit mode
	    self.write4bits(0x03 << 4)
        # Wait min 4 ms
        tasmota.delay(5)
        # second try
	    self.write4bits(0x03 << 4)
	    tasmota.delay(5) # wait min 4.1ms
    	# third go!
	    self.write4bits(0x03 << 4)
    	tasmota.delay(1)
        # set to 4-bit interface
        self.write4bits(0x02 << 4)
        # Set # lines, font size, etc.
	    self.command(self.LCD_FUNCTIONSET | displayfunction)
        # Turn the display on with no cursor or blinking default
	    self.displaycontrol = self.LCD_DISPLAYON | self.LCD_CURSOROFF | self.LCD_BLINKOFF
    	self.display()
        # Clear the screen
        self.clear()
        # Initialize to default text direction (for roman languages)
	    self.displaymode = self.LCD_ENTRYLEFT | self.LCD_ENTRYSHIFTDECREMENT
        # Set the entry mode
        self.command(self.LCD_ENTRYMODESET | self.displaymode)
        # Set cursor position to zero
        self.home()
    end

    #********** High level commands, for the user! **********

    def clear()
        self.command(self.LCD_CLEARDISPLAY)
    end
    # Set cursor position to zero
    def home()
        self.command(self.LCD_RETURNHOME)
        tasmota.delay(2)
    end
    # Set cursor position. First row and column is 1 not zero 
    def set_cursor(col, row)
        var row_offsets = [0x00, 0x40, 0x14, 0x54]
        if row > self.rows
            row = self.rows-1 
        end
        self.command(self.LCD_SETDDRAMADDR | (col-1 + row_offsets[row-1]))
    end
    # Turn the display on/off (quickly)
    def no_display()
        self.displaycontrol &= ~self.LCD_DISPLAYON
        self.command(self.LCD_DISPLAYCONTROL | self.displaycontrol)
    end
    def display()
        self.displaycontrol |= self.LCD_DISPLAYON
        self.command(self.LCD_DISPLAYCONTROL | self.displaycontrol)
    end
    # Turns the underline cursor on/off
    def no_cursor()
	    self.displaycontrol &= ~self.LCD_CURSORON
	    self.command(self.LCD_DISPLAYCONTROL | self.displaycontrol)
    end
    def cursor()
	    self.displaycontrol |= self.LCD_CURSORON
	    self.command(self.LCD_DISPLAYCONTROL | self.displaycontrol)
    end
    # TTurn on and off the blinking cursor
    def no_blink()
	    self.displaycontrol &= ~self.LCD_BLINKON
	    self.command(self.LCD_DISPLAYCONTROL | self.displaycontrol)
    end
    def blink()
	    self.displaycontrol |= self.LCD_BLINKOFF
	    self.command(self.LCD_DISPLAYCONTROL | self.displaycontrol)
    end
    # This is for text that flows Left to Right
    def display_left()
        self.command(self.LCD_CURSORSHIFT | self.LCD_DISPLAYMOVE | self.LCD_MOVELEFT)
    end
    def display_right()
        self.command(self.LCD_CURSORSHIFT | self.LCD_DISPLAYMOVE | self.LCD_MOVERIGHT)
    end
    # This is for text that flows Left to Right
    def left_to_right()
        self.displaymode |= self.LCD_ENTRYLEFT
        self.command(self.LCD_ENTRYMODESET | self.displaymode)
    end
    # This is for text that flows Right to Left
    def right_to_left()
        self.displaymode &= ~self.LCD_ENTRYLEFT
        self.command(self.LCD_ENTRYMODESET | self.displaymode)
    end
    # This will 'right justify' text from the cursor
    def autoscroll()
        self.displaymode |= self.LCD_ENTRYSHIFTINCREMENT
        self.command(self.LCD_ENTRYMODESET | self.displaymode)
    end    
    # This will 'left justify' text from the cursor
    def no_autoscroll()
        self.displaymode &= ~self.LCD_ENTRYSHIFTINCREMENT
        self.command(self.LCD_ENTRYMODESET | self.displaymode)
    end
    # Allows us to fill the first 8 CGRAM locations with custom characters 
    def create_char(location, chars)
        location &= 0x7 # We only have 8 locations 0-7
        self.command(self.LCD_SETCGRAMADDR | (location << 3))
        for char: 0 .. 7
            self.write(chars[char])
        end
    end
    # Turn the (optional) backlight on/off
    def backlight_on()
        self.backlight = self.LCD_BACKLIGHT
        self.expand_write(0)
    end
    def backlight_off()
        self.backlight = self.LCD_NOBACKLIGHT
        self.expand_write(0)
    end
    def get_backlight()
        return self.backlight == self.LCD_BACKLIGHT
    end

    # *********** Mid level commands, for sending data/cmds ************

    def command(byte)
        self.send(byte, 0)
    end
    def write(byte)
        self.send(byte, self.Rs)
    end
    def write_line(text, line)
        if !self.LCD_LINES.has(line) return end
        import string
        self.command(self.LCD_LINES[line])
        text = self.pad(text)
        for char: 0 .. size(text) -1
            self.write(string.byte(text[char]))
        end
    end
    
    # ************ low level data pushing commands ************

    def send(byte, mode)
        mode = mode ? mode : 0
        self.write4bits(mode | (byte & 0xF0) )
        self.write4bits(mode | ((byte << 4) & 0xF0) )
    end
    def write4bits(byte)
        self.expand_write(byte)
        self.pulse_enable(byte)
    end
    def expand_write(byte)
        if self.wire != nil
            self.wire.write(self.address, self.Rg, (byte | self.backlight), 1)
        end
    end
    def pulse_enable(byte)
        self.expand_write(byte | self.En)
        tasmota.delay(self.LCD_SLEEP)
        self.expand_write(byte & ~self.En)
        tasmota.delay(self.LCD_SLEEP)
    end

    # Helper methods

    def pad(text)
        for x: size(text) .. self.cols-1  
            text += " " 
        end
        return text        
    end
    def set_backlight(on)
        if on
            self.backlight_on()
        else
            self.backlight_off()
        end
    end
end

display.lcd_i2c = lcd_i2c
return display
