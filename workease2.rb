#! /usr/bin/env ruby
# frozen_string_literal: true

require 'file-tail'
require 'time'
require 'open3'

class WorkEase
  attr_accessor :bodypart, :testing, :warn_log

  def initialize
    @warn_log = []
    @testing = false
    @runnnig = true
    @pause_until = 0
  end

  def start(keyboard_id:, mouse_id:, bodypart_activity:, feet_path:, voice_path:)
    @bodypart = bodypart_activity

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

  def activity_exceeded?(b)
    time = Time.now.to_i
    puts "level #{@bodypart[b][:activity_level]}"
    puts "time active #{time - @bodypart[b][:high_activity_start]}"
    @bodypart[b][:activity_level] == 1 &&
      time - @bodypart[b][:high_activity_start] > @bodypart[b][:max_exertion] &&
      time > @bodypart[b][:last_activity]
  end

  def check_inputs(keyboard_id, mouse_id, feet_path, voice_path)
    Thread.abort_on_exception = true
    threads = []
    threads << Thread.new { check_feet(feet_path) }
    threads << Thread.new { check_voice(voice_path) }
    threads << Thread.new { check_device(keyboard_id, mouse_id) }
    # threads << Thread.new { check_slack_call }
    # threads << Thread.new { overall_activity }
    threads.each(&:join)
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

  def check_device(keyboard_id, mouse_id)
    _stdin, stdout, _stderr, _wait_thr = Open3.popen3('xinput test-xi2 --root')
    event = nil
    stdout.each do |line|
      event = line.split.last if line.include?('EVENT type')
      next unless line.include?('device:')

      device = line.split[1]
      if [keyboard_id, mouse_id].includes?(device) && ['(ButtonPress)', '(KeyPress)', '(Motion)'].includes?(event)
        check(:hands)
      end
    end
  end

  def check(b)
    semaphore = Mutex.new
    semaphore.synchronize do
      time = Time.now.to_i
      @bodypart[b][:last_activity] = time if @bodypart[b][:last_activity].nil?

      if time - @bodypart[b][:last_activity] < @bodypart[b][:min_rest]
        if @bodypart[b][:activity_level] == 0
          @bodypart[b][:high_activity_start] = @bodypart[b][:last_activity]
        end
        @bodypart[b][:activity_level] = 1
      else
        @bodypart[b][:activity_level] = 0
        @bodypart[b][:high_activity_start] = 0
      end

      if activity_exceeded?(b)
        warn("You should give your #{b} a break, wait #{@bodypart[b][:min_rest]} seconds")
        rest_timer(@bodypart[b][:min_rest], b)
      end

      @bodypart[b][:last_activity] = time
    end
  end

  def rest_timer(time, activity)
    message = "#{activity}-break over"
    return if @testing
    Process.fork do
      sleep time
      `paplay ./service-login.ogg`
      `xmessage #{message} -center -timeout 3`
    end
  end

  def warn(reason)
    if @testing
      message = "#{Time.now} - #{reason}\n"
      @warn_log << message
    elsif Time.now.to_i > @pause_until
      `paplay ./when.ogg`
      @pause_until = Time.now.to_i + 5
      sleep 1
      Process.fork { `xmessage #{Shellwords.escape(reason)} -center -timeout 3` }
      File.open('testlog', 'a') { |f| f << "#{reason}\n" }
    end
  end
end
