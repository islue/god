God.watch do |w|
  w.name = "child-events"
  w.interval = 5.seconds
  w.start = File.join(File.dirname(__FILE__), *%w[simple_server.rb])
  
  # determine the state on startup
  w.transition(:init, { true => :up, false => :start }) do |on|
    on.condition(:process_running) do |c|
      c.running = true
    end
  end
  
  # determine when process has finished starting
  w.transition(:start, :up) do |on|
    on.condition(:process_running) do |c|
      c.running = true
    end
    
    on.condition(:tries) do |c|
      c.times = 2
      c.transition = :start
    end
  end

  # start if process is not running
  w.transition(:up, :start) do |on|
    on.condition(:process_exits)
  end
end