#!/usr/local/bin/ruby -w

# $Id$

# the class responsible for actually doing any work

# enables no-op and logging/rollback

module Puppet
	class StateChange
        attr_accessor :is, :should, :type, :path, :state, :transaction, :changed

		#---------------------------------------------------------------
        def initialize(state)
            @state = state
            @path = [state.path,"change"].flatten
            @is = state.is

            if state.is == state.should
                raise Puppet::Error.new(
                    "Tried to create a change for in-sync state %s" % state.name
                )
            end
            @should = state.should

            @changed = false
        end
		#---------------------------------------------------------------

		#---------------------------------------------------------------
        def go
            if @state.is == @state.should
                Puppet.info "%s.%s is already in sync" %
                    [@state.parent.name, @state.name]
                return nil
            end

            if @state.noop
                @state.parent.log "%s should be %s" %
                    [@state, @should]
                #Puppet.debug "%s is noop" % @state
                return nil
            else
                Puppet.notice "Noop is %s" % @state.noop
            end

            begin
                events = @state.sync
                if events.nil?
                    return nil
                end

                if events.is_a?(Array)
                    if events.empty?
                        return nil
                    end
                else
                    events = [events]
                end
                
                return events.collect { |event|
                    # default to a simple event type
                    if ! event.is_a?(Symbol)
                        Puppet.warning("State '%s' returned invalid event '%s'; resetting to default" %
                            [@state.class,event])

                        event = @state.parent.class.name.id2name + "_changed"
                    end

                    # i should maybe include object type, but the event type
                    # should basically point to that, right?
                        #:state => @state,
                        #:object => @state.parent,
                    # FIXME this is where loglevel stuff should go
                    @state.parent.log @state.change_to_s
                    Puppet::Event.new(
                        :event => event,
                        :change => self,
                        :transaction => @transaction,
                        :source => @state.parent,
                        :message => self.to_s
                    )
                }
            rescue => detail
                #Puppet.err "%s failed: %s" % [self.to_s,detail]
                raise
                # there should be a way to ask the state what type of event
                # it would have generated, but...
                pname = @state.parent.class.name.id2name
                #if pname.is_a?(Symbol)
                #    pname = pname.id2name
                #end
                    #:state => @state,
                @state.parent.log "Failed: " + @state.change_to_s
                return Puppet::Event.new(
                    :event => pname + "_failed",
                    :change => self,
                    :source => @state.parent,
                    :transaction => @transaction,
                    :message => "Failed: " + self.to_s
                )
            end
        end
		#---------------------------------------------------------------

		#---------------------------------------------------------------
        def forward
            #Puppet.debug "moving change forward"

            unless defined? @transaction
                raise Puppet::Error,
                    "StateChange '%s' tried to be executed outside of transaction" %
                    self
            end

            return self.go
        end
		#---------------------------------------------------------------

		#---------------------------------------------------------------
        def backward
            @state.should = @is
            @state.retrieve

            unless defined? @transaction
                raise Puppet::Error,
                    "StateChange '%s' tried to be executed outside of transaction" %
                    self
            end
            unless @state.insync?
                Puppet.info "Backing %s" % self
                return self.go
            else
                Puppet.debug "rollback is already in sync: %s vs. %s" %
                    [@state.is.inspect, @state.should.inspect]
                return nil
            end

            #raise "Moving statechanges backward is currently unsupported"
            #@type.change(@path,@should,@is)
        end
		#---------------------------------------------------------------
        
		#---------------------------------------------------------------
        def noop
            return @state.noop
        end
		#---------------------------------------------------------------

        def to_s
            return "change %s.%s(%s)" %
                [@transaction.object_id, self.object_id, @state.change_to_s]
            #return "change %s.%s" % [@transaction.object_id, self.object_id]
        end
	end
end
