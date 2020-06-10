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
    @running = true
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
    threads << Thread.new { check_slack_call }
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
      if [keyboard_id, mouse_id].include?(device) && ['(ButtonPress)', '(KeyPress)', '(Motion)'].include?(event)
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

  def check_slack_call
    @call_started = nil
    @call_ended = nil
    @last_warning = nil
    @last_call_duration = 0
    while @running
      call_logic
      sleep 60
    end
  end

  def call_logic
    slack_call = slack_call_found?
    @call_started = Time.now.to_i if slack_call && @call_started.nil?
    @call_active = true if slack_call

    # when hanging up, store some info about last call
    if !slack_call && @call_ended.nil? && !@call_started.nil?
      @call_active = false
      @call_ended = Time.now.to_i
      @last_call_duration = @call_ended - @call_started
    end
    @call_started = nil if @call_ended && !slack_call

    # reset timers if last call ended more than 10 minutes ago
    if @call_ended && !slack_call && (@call_ended + 600) <= Time.now.to_i
      @last_warning = nil
      @call_ended = nil
      @last_call_duration = 0
    end

    # warn if current call, or current plus last call is longer than 45 min
    if @call_started && Time.now.to_i - @call_started >= 2700 || @call_started && @last_call_duration && (Time.now.to_i - @call_started + @last_call_duration) >= 2700
      return if @last_warning && (Time.now.to_i - @last_warning < 300)
      warn('You have been on a call for over 45 minutes, take a 10 minute break')
      sleep 4
      rest_timer(600, 'slack_call')
      @last_warning = Time.now.to_i
    end
  end

  private

  def rest_timer(time, activity)
    message = "#{activity}-break over"
    return if @testing

    Process.fork do
      sleep time
      `paplay ./service-login.ogg`
      `xmessage #{message} -center -timeout 3`
    end
  end

  def slack_call_found?
    xids = `xdotool search --class --classname --name slack`.split("\n")
    return false if $?.exitstatus > 0

    xids.find do |xid|
      !`xwininfo -all -id "#{xid}"| grep "Slack call with"`.strip.empty?
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
