#! /usr/bin/env ruby

require 'file-tail'
require 'time'
require 'pry'
require 'open3'

class WorkEase
  def start(keyboard_id:, mouse_id:, bodypart_activity:, feet_path:, voice_path:)
    @bodypart = bodypart_activity
    @pause_until = 0

    File.truncate('commands', 0)

    check_inputs(keyboard_id, mouse_id, feet_path, voice_path)
  end

  def self.find_device_ids(keyboard_name:, mouse_name:)
    output = `xinput`
    output.split("\n").each do |line|
      if line.include?(keyboard_name)
        line.split(' ').each do |word|
          @keyboard_id = word.delete_prefix('id=') if word.start_with?('id=')
        end
      end
      next unless line.include?(mouse_name)
      line.split(' ').each do |word|
        @mouse_id = word.delete_prefix('id=') if word.start_with?('id=')
      end
    end
    [@keyboard_id, @mouse_id]
  end

  def check_inputs(keyboard_id, mouse_id, feet_path, voice_path)
    Thread.abort_on_exception = true
    threads = []
    threads << Thread.new { check_commands }
    threads << Thread.new { check_feet(feet_path) }
    threads << Thread.new { check_voice(voice_path) }
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

  def check_feet(feet_path)
    File::Tail::Logfile.tail(feet_path, backward: 1, interval: 0.1) do |_line|
      check(:feet)
    end
  end

  def check_voice(voice_path)
    File::Tail::Logfile.tail(voice_path, backward: 1, interval: 0.1) do |_line|
      check(:voice)
    end
  end

  def check_device(id)
    _stdin, stdout, _stderr, _wait_thr = Open3.popen3('xinput test-xi2 --root')
    event = nil
    stdout.each do |line|
      event = line.split.last if line.include?('EVENT type')
      next unless line.include?('device:')
      device = line.split[1]
      # TODO: get rid of hardcoded device id used in testing env
      if (device == id || device.to_i == 13) && event == '(ButtonPress)' || event == '(KeyPress)' || event == '(Motion)'
        check(:hands)
      end
    end
  end

  def activity_exceeded?(b)
    time = Time.now.to_i
    puts "level #{@bodypart[b][:activity_level]}"
    puts "time active #{time - @bodypart[b][:high_activity_start]}"
    @bodypart[b][:activity_level] == 1 &&
      time - @bodypart[b][:high_activity_start] > @bodypart[b][:max_exertion] &&
      time > @bodypart[b][:last_activity]
  end

  def check(b)
    semaphore = Mutex.new
    semaphore.synchronize do
      time = Time.now.to_i
      @bodypart[b][:last_activity] = time if @bodypart[b][:last_activity].nil?

      if time - @bodypart[b][:last_activity] < @bodypart[b][:min_rest]
        @bodypart[b][:high_activity_start] = @bodypart[b][:last_activity] if @bodypart[b][:activity_level] == 0
        @bodypart[b][:activity_level] = 1
      else
        @bodypart[b][:activity_level] = 0
        @bodypart[b][:high_activity_start] = 0
      end

      warn("You should give your #{b} a break") if activity_exceeded?(b)

      @bodypart[b][:last_activity] = time
    end
  end

  def warn(reason)
    if Time.now.to_i > @pause_until
      `paplay ./when.ogg`
      sleep 1
      Process.fork { `xmessage #{reason} -center -timeout 3` }
      @pause_until = Time.now.to_i + 3
      File.open('testlog', 'a') { |f| f << "#{reason}\n" }
    end
  end
end
