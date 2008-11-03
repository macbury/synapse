#
# synapse: a small XMPP server
# xmpp/parser.rb: parse and do initial XML processing
#
# Copyright (c) 2006-2008 Eric Will <rakaur@malkier.net>
#
# $Id$
#

#
# The XMPP namespace.
#
module XMPP

#
# The Process namespace.
# This is meant to be a mixin to a Stream.
#
module Process
    
def process_stanza(stanza)
    s_type = stanza.name
    s_to   = stanza.attributes['to']
    
    # Section 11.1 - no 'to' attribute
    #   Server MUST handle directly.
    if not s_to or s_to.empty?
        if server?
            $log.s2s.error "Got bad stanza from #{@host}: " +
                           "'#{s_type}' (no 'to' attribute)"

            error('bad-format')
        else
            # Section 11.1.2 - message
            #   Server MUST treat as if 'to' is the bare JID of the sender.
            if s_type == 'message'
                stanza.add_attribute('to', @resource.user.jid)
                process_stanza(stanza)

            # Section 11.1.3 - presence
            #   Server MUST broadcast according to XMPP-IM.
            elsif s_type == 'presence'
                p_type = stanza.attributes['type']

                if not p_type
                    presence_none(stanza)
                elsif p_type =~ /^(unavailable|(un)?subscribe(d)?)$/
                    send("presence_#{p_type}", stanza)
                else
                    write Stanza.error(stanza, 'bad-request', 'modify')
                end

            # Section 11.1.4 - iq
            #   Server MUST process on behalf of the account that received it.
            elsif s_type == 'iq'
                # Just handle it as if it were to our domain.
                stanza.add_attribute('to', @myhost)
                process_stanza(stanza)

            # All other recognized stanzas.
            else
                send("handle_#{s_type}", stanza)
            end
        end
    else
        # Separate out the JID parts in the 'to' attribute.
        node,   domain   = s_to.split('@')
        domain, node     = node, domain if node and not domain
        domain, resource = domain.split('/')

        # Stamp the 'from' field.
        stanza.add_attribute('from', @resource.jid) if @resource

        # Section 11.2 - local domain
        #   Server MUST process
        if $config.hosts.include?(domain)
            # Section 11.2.1 - mere domain
            #   Server MUST handle based on stanza type.
            if not node and not resource
                if s_type == 'iq'
                    handle_local_iq(stanza)
                else
                    write Stanza.error(stanza, 'bad-request', 'modify')
                end
                
            # Section 11.2.2 - domain with resource
            #   Server MUST handle based on stanza type.
            elsif not node and resource
                # 11.2.2 - domain with resource
                #   I have no idea what this could possibly apply to at
                #   the moment, so for now we error.
                write Stanza.error(stanza, 'bad-request', 'modify')
                
            # Section 11.2.3 - node at domain
            #   Rules defined in XMPP-IM - XXX
            elsif node and domain
                user = DB::User.users[node + '@' + domain]
                
                # Section 11.2.3.1 - no such user
                #   Ignore 'presence'
                if not user and s_type =~ /(message|iq)/
                    write Stanza.error(stanza, 'service-unavailable', 'cancel')
                    return
                end
                
                # Section 11.2.3.2 - bare jid
                if not resource
                    if s_type == 'message'
                        if user.available? # Deliver to local user.
                            user.front_resource.stream.write stanza
                        else # Store it offline.
                            # This implements XEP-0203.
                            dt = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
                            delay = REXML::Element.new('delay')
                            delay.add_attribute('stamp', dt)
                            delay.add_attribute('from', @myhost)
                            delay.add_namespace('urn:xmpp:delay')
                            delay.text = 'Offline Storage'

                            stanza << delay
                            user.offline_stanzas << stanza.to_s

                            @logger.unknown "Last message stored offline"
                        end
                    elsif s_type == 'presence'
                        p_type = stanza.attributes['type']
                        sb     = user.subscribed?(@resource.user)

                        # This is directed presence.
                        if user.available?
                            user.resources.each do |n, rec|
                                rec.stream.write stanza

                                if p_type !~ /((un)?subscribe(d)?)/
                                    @resource.dp_to << rec.jid unless sb
                                end
                            end

                        elsif p_type =~ /((un)?subscribe(d)?)/
                            # This implements XEP-0203.
                            dt = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
                            delay = REXML::Element.new('delay')
                            delay.add_attribute('stamp', dt)
                            delay.add_attribute('from', @myhost)
                            delay.add_namespace('urn:xmpp:delay')
                            delay.text = 'Offline Storage'

                            stanza << delay
                            user.offline_stanzas << stanza.to_s

                            @logger.unknown "Last presence stored offline"
                        end
                    elsif s_type == 'iq'
                        # XXX - handle on behalf of user
@logger.unknown '--> previous stanza unhandled <--'
@logger.unknown "--> at %s:%d" % [__FILE__.split('/')[-1], __LINE__]                    end        
                            
                # Section 11.2.3.3 - full jid
                else
                    rec   = user.resources[resource] if user.resources
                    rec ||= nil

                    if rec
                        rec.stream.write stanza
                    else
                        stanza.add_attribute('to', node + '@' + domain)
                        process_stanza(stanza)
                    end
                end
            # All other recognized stanzas.
            else
                # Should we ever get here?
                #   This should only happen if something other than
                #   message/iq/presence has a "to" field. I don't think
                #   think this can happen.
                $log.c2s.info "Handling a weird stanza: #{stanza.to_s}"
                send("handle_#{stanza.name}", stanza)
            end
        # Section 11.3 - foreign domain
        #   Server SHOULD attempt to route.
        else
            # XXX - s2s
            write Stanza.error(stanza, 'FEATURE-NOT-IMPLEMENTED', 'cancel')
        end
    end
end

end # module Process
end # module XMPP