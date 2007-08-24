$:.unshift File.dirname(__FILE__)     # For use/testing when no gem is installed

require 'syslog'

# internal requires
require 'god/errors'

require 'god/system/process'

require 'god/behavior'
require 'god/behaviors/clean_pid_file'

require 'god/condition'
require 'god/conditions/timeline'
require 'god/conditions/process_running'
require 'god/conditions/process_exits'
require 'god/conditions/tries'
require 'god/conditions/memory_usage'
require 'god/conditions/cpu_usage'
require 'god/conditions/always'

require 'god/reporter'
require 'god/server'
require 'god/timer'
require 'god/hub'

require 'god/metric'
require 'god/watch'

require 'god/event_handler'
require 'god/registry'
require 'god/process'

require 'god/sugar'

$:.unshift File.join(File.dirname(__FILE__), *%w[.. ext god])

begin
  Syslog.open('god')
rescue RuntimeError
  Syslog.reopen('god')
end

God::EventHandler.load

module God
  VERSION = '0.3.0'
  
  class << self
    attr_accessor :inited, :host, :port
    
    # drb
    attr_accessor :server
    
    # api
    attr_accessor :watches, :groups
  end
  
  def self.init
    # only do this once
    return if self.inited
    
    # variable init
    self.watches = {}
    self.groups = {}
    
    # yield to the config file
    yield self if block_given?
    
    # instantiate server
    self.server = Server.new(self.host, self.port)
    
    # init has been executed
    self.inited = true
  end
    
  # Where pid files created by god will go by default
  def self.pid_file_directory
    @pid_file_directory ||= '/var/run/god'
  end
  
  def self.pid_file_directory=(value)
    @pid_file_directory = value
  end
  
  # Instantiate a new, empty Watch object and pass it to the mandatory
  # block. The attributes of the watch will be set by the configuration
  # file.
  def self.watch
    self.init
    
    w = Watch.new
    yield(w)
    
    # ensure the new watch has a unique name
    if self.watches[w.name] || self.groups[w.name]
      abort "Watch name '#{w.name}' already used for a Watch or Group"
    end
    
    # add to list of watches
    self.watches[w.name] = w
    
    # add to group if specified
    if w.group
      # ensure group name hasn't been used for a watch already
      if self.watches[w.group]
        abort "Group name '#{w.group}' already used for a Watch"
      end
    
      self.groups[w.group] ||= []
      self.groups[w.group] << w
    end

    # register watch
    w.register!
  end
  
  def self.control(name, command)
    # get the list of watches
    watches = Array(self.watches[name] || self.groups[name])
  
    # do the command
    case command
      when "start", "monitor"
        watches.each { |w| w.monitor }
      when "restart"
        watches.each { |w| w.move(:restart) }
      when "stop"
        watches.each { |w| w.unmonitor.action(:stop) }
      when "unmonitor"
        watches.each { |w| w.unmonitor }
      else
        raise InvalidCommandError.new
    end
    
    watches
  end
    
  def self.start
    # make sure there's something to do
    if self.watches.nil? || self.watches.empty?
      abort "You must specify at least one watch!"
    end
    
    # start event handler system
    EventHandler.start if EventHandler.loaded?
    
    # start the timer system
    Timer.get

    # start monitoring any watches set to autostart
    self.watches.values.each { |w| w.monitor if w.autostart? }
    
    # join the timer thread so we don't exit
    Timer.get.join
  end
  
  def self.at_exit
    self.start
  end
  
  def self.load(glob)
    Dir[glob].each do |f|
      Kernel.load f
    end
  end
end

at_exit do
  God.at_exit
end