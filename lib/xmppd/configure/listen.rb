#
# xmppd: a small XMPP server
# listen.rb: port listening configuration
#
# Copyright (c) 2006 Eric Will <rakaur@malkier.net>
#
# $Id$
#

module Configure

#
# Represents listen{} configuration data.
#
class Listen
    attr_accessor :c2s, :s2s

    def initialize
        @c2s = []
        @s2s = []
    end
end

end # module Configure
