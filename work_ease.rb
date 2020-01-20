#! /usr/bin/env ruby

require 'file-tail'
require 'time'
require 'pry'

class WorkEase
  def start
    @bodypart = {
      'feet' =>
        {:last_activity => nil,
         :activity_level => 0,
         :min_rest => 5, # 60
         :max_exertion => 50, # 600
         :high_activity_start => nil
      },
      'hands' =>
        {:last_activity => nil,
         :min_rest => 10,
         :activity_level => 0,
         :max_exertion => 20, # 120
         :high_activity_start => nil
      },
      'voice' =>
        {:last_activity => nil,
         :min_rest => 10,
         :activity_level => 0,
         :max_exertion => 20,# 120
         :high_activity_start => nil
      }
    }

    @counter = 0

    @pause_untill = 0

    File.truncate('commands', 0)

    check_inputs
  end

  def check_inputs
    semaphore = Mutex.new
    threads = []
    threads << Thread.new { check_commands }
    threads << Thread.new { check_feet }
    threads << Thread.new { check_voice }
    threads << Thread.new { semaphore.synchronize { check_keyboard } }
    threads << Thread.new { semaphore.synchronize { check_mouse } }
    threads.each(&:join)
  end

  def check_commands
    File::Tail::Logfile.tail('commands', :backward => 1, :interval => 0.5) do |line|
      if line.start_with?('suspend')
        seconds = line.split[1]
        puts "pausing monitoring for #{seconds} seconds"
        @pause_untill = Time.now.to_i + seconds
      end

      # if line.start_with?('set feet_warning')
      #   warning = line.split.drop(2).join(' ')
      #   puts warning
      # end
    end
  end

  def check_feet
    File::Tail::Logfile.tail('inputs/feet', :backward => 1, :interval => 0.1) do |line|
      check('feet')
    end
  end

  def check_keyboard
    File::Tail::Logfile.tail('inputs/keyboard', :backward => 1, :interval => 0.1) do |line|
      check('hands')
    end
  end

  def check_mouse
    File::Tail::Logfile.tail('inputs/mouse', :backward => 1, :interval => 0.1) do |line|
      check('hands')
    end
  end

  def check_voice
    File::Tail::Logfile.tail('inputs/voice', :backward => 1, :interval => 0.1) do |line|
      check('voice')
    end
  end

  def activity_exceeded?(b)
    puts "level #{@bodypart[b][:activity_level]}"
    puts "time active #{Time.now.to_i - @bodypart[b][:high_activity_start]}"
    @bodypart[b][:activity_level] == 1 &&
    Time.now.to_i - @bodypart[b][:high_activity_start] > @bodypart[b][:max_exertion]
  end

  def check(b)
    puts "-------- #{@counter += 1}"
    @bodypart[b][:last_activity] = Time.now.to_i if @bodypart[b][:last_activity].nil?

    if Time.now.to_i - @bodypart[b][:last_activity] < @bodypart[b][:min_rest]
      @bodypart[b][:high_activity_start] = @bodypart[b][:last_activity] if @bodypart[b][:activity_level] == 0
      @bodypart[b][:activity_level] = 1
    else
      @bodypart[b][:activity_level] = 0
      @bodypart[b][:high_activity_start] = 0
    end

    warn("You should give your #{b} a break") if activity_exceeded?(b)

    @bodypart[bodypart][:last_activity] = Time.now.to_i
  end

  def warn(reason)
    puts reason if Time.now.to_i > @pause_untill
  end
end