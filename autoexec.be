#  ------------------------------------------------------------------------------------------------------
#  autoexec.be - Berry scripting language
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

import global

class module_loader
    var wd, cache
    def init()
        self.wd = tasmota.wd
        self.cache = []
    end
    def require(module)
        if self.cache.find(module) != nil 
            return 
        end
        if size(self.wd)
            import sys
            # Add tapp path to sys.path
            sys.path().push(self.wd)
            # Load module from file system
            load(self.wd + module)
            self.push(module)
            # Remove tapp path from sys.path
            sys.path().pop()
        else
            load(self.wd + module)
            self.push(module)
        end
    end
    def push(module)
        if self.cache.find(module) == nil
            self.cache.push(module)
        end
    end
end

var loader = module_loader()
# Load heating.be from file system
loader.require('heating.be')
# Initialise heating controller
var hc = global.heating.controller()
# Start the heating controller
hc.start()