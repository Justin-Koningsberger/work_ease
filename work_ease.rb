#! /usr/bin/env ruby

require 'file-tail'
require 'time'
require 'pry'

class WorkEase
  def  start
    @last_feet_activity
    @feet_activity_level = 0
    @feet_min_rest = 5 # 60
    @feet_max_exertion = 50 # 600
    @feet_high_activity_start

    @last_voice_activity
    @voice_min_rest = 10
    @voice_activity_level = 0
    @voice_max_exertion = 20 # 120
    @voice_high_activity_start

    @last_hands_activity
    @hands_min_rest = 5 # 50
    @hands_activity_level = 0
    @hands_max_exertion = 18 # 180
    @hands_high_activity_start

    # File.truncate('commands', 0)

    # check commands
    check_inputs
  end

  def check_inputs
    semaphore = Mutex.new
    threads = []
    threads << Thread.new { check_feet }
    threads << Thread.new { check_voice }
    threads << Thread.new { semaphore.synchronize { check_mouse} }
    threads << Thread.new { semaphore.synchronize { check_keyboard } }
    threads.each(&:join)
  end

  def feet_activity_exceeded?
    @feet_activity_level == 1 &&
    Time.now.to_i - @feet_high_activity_start > @feet_max_exertion
  end

  def check_feet
    File::Tail::Logfile.tail('inputs/feet', :backward => 1, :interval => 0.1) do |line|
      @last_feet_activity = Time.now.to_i if @last_feet_activity.nil?

      if Time.now.to_i - @last_feet_activity < @feet_min_rest
        @feet_high_activity_start = @last_feet_activity if @feet_activity_level == 0
        @feet_activity_level = 1
      else
        @feet_activity_level = 0
        @feet_high_activity_start += @feet_min_rest # maybe * 2 or = Time.now.to_i
      end

      warn("You should rest your feet") if feet_activity_exceeded?

      @last_feet_activity = Time.now.to_i
    end
  end

  def voice_activity_exceeded?
    @voice_activity_level == 1 &&
    Time.now.to_i - @voice_high_activity_start > @voice_max_exertion
  end

  def check_voice
    File::Tail::Logfile.tail('inputs/voice', :backward => 1, :interval => 0.1) do |line|
      @last_voice_activity = Time.now.to_i if @last_voice_activity.nil?

      if Time.now.to_i - @last_voice_activity < @voice_min_rest
        @voice_high_activity_start = @last_voice_activity if @voice_activity_level == 0
        @voice_activity_level = 1
      else
        @voice_activity_level = 0
        @voice_high_activity_start += @voice_min_rest # maybe * 2 or = Time.now.to_i
      end
      
      warn("You should give your voice a break") if voice_activity_exceeded?

      @last_voice_activity = Time.now.to_i
    end
  end

  def check_keyboard
    File::Tail::Logfile.tail('inputs/keyboard', :backward => 1, :interval => 0.1) do |line|
      hands_check
    end
  end

  def check_mouse
    File::Tail::Logfile.tail('inputs/mouse', :backward => 1, :interval => 0.1) do |line|
      hands_check
    end
  end

  def hands_activity_exceeded?
    # puts "level #{@mouse_activity_level}"
    # puts "time active #{Time.now.to_i - @mouse_high_activity_start}"
    @hands_activity_level == 1 &&
    Time.now.to_i - @hands_high_activity_start > @hands_max_exertion
  end

  def hands_check
    @last_hands_activity = Time.now.to_i if @last_hands_activity.nil?

    if Time.now.to_i - @last_hands_activity < @hands_min_rest
      @hands_high_activity_start = @last_hands_activity if @hands_activity_level == 0
      @hands_activity_level = 1
    else
      @hands_activity_level = 0
      @hands_high_activity_start += @hands_min_rest # maybe * 2 or = Time.now.to_i
    end
    
    warn("You should give your hands a break") if hands_activity_exceeded?

    @last_hands_activity = Time.now.to_i
  end

  def warn(reason)
    puts reason
  end
end