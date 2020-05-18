#! /usr/bin/env ruby
# frozen_string_literal: true

require 'file-tail'
require 'time'
require 'pry'
require 'open3'

class WorkEase
  def start(keyboard_id:, mouse_id:, bodypart_activity:, feet_path:, voice_path:)
    @bodypart = bodypart_activity
    @pause_until = 0

    # File.truncate('commands', 0)

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
    puts @mouse_id
    puts @mouse_id.inspect
    puts @keyboard_id
    puts @keyboard_id.inspect
    [@keyboard_id, @mouse_id]
  end

  def check_inputs(keyboard_id, mouse_id, feet_path, voice_path)
    Thread.abort_on_exception = true
    threads = []
    # threads << Thread.new { check_commands }
    threads << Thread.new { check_feet(feet_path) }
    threads << Thread.new { check_voice(voice_path) }
    threads << Thread.new { check_device(keyboard_id, mouse_id) }
    threads << Thread.new { check_slack_call }
    threads << Thread.new { overall_activity }
    threads.each(&:join)
  end

  def overall_activity
    time_active = nil
    interval = 3 * 60
    puts 'Start overall activity counter'
    loop do
      time = Time.now.to_i
      feet_active = nil_check(@bodypart[:feet][:last_activity], time, interval)
      hands_active = nil_check(@bodypart[:hands][:last_activity], time, interval)
      voice_active = nil_check(@bodypart[:voice][:last_activity], time, interval)
      call_active = @call_active.nil? ? false : @call_active

      if feet_active || hands_active || voice_active || call_active
        time_active = Time.now.to_i if time_active.nil?
        puts "Overall time active: #{time - time_active} seconds"
      else
        time_active = nil
      end

      unless time_active.nil?
        messg = "You have been fairly active for #{(time - time_active) / 60} minutes, take a ten minute break"
      end
      warn(messg) if !time_active.nil? && time - time_active >= 50 * 60

      sleep interval
    end
  end

  def check_commands
    File::Tail::Logfile.tail('commands', backward: 1, interval: 0.5) do |line|
      if line.start_with?('suspend')
        seconds = line.split[1].to_i
        puts "pausing monitoring for #{seconds} seconds"
        @pause_until = Time.now.to_i + seconds
      end
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

  def check_device(keyboard_id, mouse_id)
    _stdin, stdout, _stderr, _wait_thr = Open3.popen3('xinput test-xi2 --root')
    event = nil
    stdout.each do |line|
      event = line.split.last if line.include?('EVENT type')
      next unless line.include?('device:')

      device = line.split[1]
      if (device == keyboard_id || device == mouse_id) && (event == '(ButtonPress)' || event == '(KeyPress)' || event == '(Motion)')
        check(:hands)
      end
    end
  end

  def check_slack_call
    call_started = nil
    call_ended = nil
    last_warning = nil
    loop do
      xids = `xdotool search --class --classname --name slack`.split("\n")
      check_exit_status("xdotool")
      slack_call = xids.find do |xid|
        !`xwininfo -all -id "#{xid}"| grep "Slack call with"`.strip.empty?
        check_exit_status("xwininfo")
      end
      call_started = Time.now.to_i if slack_call && call_started.nil?
      @call_active = true if slack_call
      # puts "call duration: #{Time.now.to_i - call_started}" if call_started
      if !slack_call && call_ended.nil? && !call_started.nil?
        @call_active = false
        call_ended = Time.now.to_i
      end
      # puts "call ended for: #{Time.now.to_i - call_ended}" if call_ended

      call_started = nil if call_ended && !slack_call
      if call_ended && (call_ended + 600) <= Time.now.to_i
        # puts "reset monitoring"
        last_warning = nil
        call_ended = nil
      end

      if call_started && Time.now.to_i - call_started.to_i > 2700
        warn('You have been on a call for over 45 minutes, take a 10 minute break')
        sleep 4
        rest_timer(600, 'slack_call')
        # puts "warning"
        last_warning = Time.now.to_i
      end
      sleeptime = last_warning.nil? ? 60 : 300
      sleep sleeptime
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
    Process.fork do
      sleep time
      `paplay ./service-login.ogg`
      `xmessage #{activity}-break over -center -timeout 3`
    end
  end

  def warn(reason)
    if Time.now.to_i > @pause_until
      `paplay ./when.ogg`
      @pause_until = Time.now.to_i + 5
      sleep 1
      Process.fork { `xmessage #{Shellwords.escape(reason)} -center -timeout 3` }
      File.open('testlog', 'a') { |f| f << "#{reason}\n" }
    end
  end
end

private

def check_exit_status(program)
  if $?.exitstatus > 0
    messg = "#{program} ran into an error, exitstatus: #{$?.exitstatus}"
    `paplay ./dialog-error.ogg`
    sleep 1
    Process.fork { `xmessage messg -center -timeout 3` }
  end
end

def nil_check(object, time, interval)
  object.nil? ? false : time - object <= interval
end
