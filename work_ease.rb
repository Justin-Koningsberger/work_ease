#! /usr/bin/env ruby

require 'file-tail'
require 'time'
require 'pry'
require 'open3'

class WorkEase
  def start(keyboard_id:, mouse_id:, bodypart_activity:)
    @bodypart = bodypart_activity
    @pause_until = 0

    File.truncate('commands', 0)

    check_inputs(keyboard_id, mouse_id)
  end

  def self.find_device_ids(keyboard_name:, mouse_name:)
    output = `xinput`
    output.split("\n").each do |line|
      if line.include?(keyboard_name)
        line.split(' ').each do |word|
          @keyboard_id = word[-1] if word.start_with?('id=')
        end
      end
      next unless line.include?(mouse_name)
      line.split(' ').each do |word|
        @mouse_id = word[-1] if word.start_with?('id=')
      end
    end
    [@keyboard_id, @mouse_id]
  end

  def check_inputs(keyboard_id, mouse_id)
    Thread.abort_on_exception = true
    threads = []
    threads << Thread.new { check_commands }
    threads << Thread.new { check_feet }
    threads << Thread.new { check_voice }
    threads << Thread.new { check_device(keyboard_id) }
    threads << Thread.new { check_device(mouse_id) }
    threads.each(&:join)
  end

  def check_commands
    File::Tail::Logfile.tail('commands', backward: 1, interval: 0.5) do |line|
      if line.start_with?('suspend')
        seconds = line.split[1].to_i
        puts "pausing monitoring for #{seconds} seconds"
        @pause_until = Time.now.to_i + seconds
      end

      # if line.start_with?('set feet_warning')
      #   warning = line.split.drop(2).join(' ')
      #   puts warning
      # end
    end
  end

  def check_feet
    File::Tail::Logfile.tail('inputs/feet', backward: 1, interval: 0.1) do |_line|
      check(:feet)
    end
  end

  def check_voice
    File::Tail::Logfile.tail('inputs/voice', backward: 1, interval: 0.1) do |_line|
      check(:voice)
    end
  end

  def check_device(id)
    _stdin, stdout, _stderr, _wait_thr = Open3.popen3("xinput test #{id}")
    stdout.each do |line|
      check(:hands) unless line.start_with?('key press')
    end
  end

  def activity_exceeded?(b)
    puts "level #{@bodypart[b][:activity_level]}"
    puts "time active #{Time.now.to_i - @bodypart[b][:high_activity_start]}"
    @bodypart[b][:activity_level] == 1 &&
      Time.now.to_i - @bodypart[b][:high_activity_start] > @bodypart[b][:max_exertion]
  end

  def check(b)
    semaphore = Mutex.new
    semaphore.synchronize do
      @bodypart[b][:last_activity] = Time.now.to_i if @bodypart[b][:last_activity].nil?

      if Time.now.to_i - @bodypart[b][:last_activity] < @bodypart[b][:min_rest]
        @bodypart[b][:high_activity_start] = @bodypart[b][:last_activity] if @bodypart[b][:activity_level] == 0
        @bodypart[b][:activity_level] = 1
      else
        @bodypart[b][:activity_level] = 0
        @bodypart[b][:high_activity_start] = 0
      end

      warn("You should give your #{b} a break") if activity_exceeded?(b)

      @bodypart[b][:last_activity] = Time.now.to_i
    end
  end

  def warn(reason)
    if Time.now.to_i > @pause_until
      `paplay ./when.ogg`
      sleep 2
      Process.fork { `xmessage #{reason} -center -timeout 3` }
      File.open('testlog', 'a') { |f| f << "#{reason}\n" }
    end
  end
end
