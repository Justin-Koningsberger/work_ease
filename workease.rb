#! /usr/bin/env ruby
# frozen_string_literal: true

require 'active_support/time'
require 'English'
require 'file-tail'
require 'shellwords'
require 'time'
require 'open3'

class WorkEase
  attr_accessor :state, :testing, :warn_log, :semaphore

  OVERALL_ACTIVITY_INTERVAL = 3.minutes
  OVERALL_ACTIVITY_LIMIT = 50.minutes
  OVERALL_ACTIVITY_WARNING_SNOOZE = 5.minutes
  TAIL_INTERVAL = 0.1
  SLACK_CALL_INTERVAL = 1.minute
  SLACK_CALL_LIMIT = 28.minutes
  SLACK_REST_TIME = 10.minutes
  SLACK_WARNING_SNOOZE = 5.minutes
  STRETCH_TIME = 15.minutes

  def initialize(keyboard_id:, mouse_id:, bodypart_activity:, feet_path:, voice_path:)
    @state = bodypart_activity
    @feet_path = feet_path
    @keyboard_id = keyboard_id
    @mouse_id = mouse_id
    @pause_until = 0
    @running = true
    @semaphore = Mutex.new
    @testing = false
    @voice_path = voice_path
    @warn_log = []
    @inactive_for_hour = false
  end

  def start
    Thread.abort_on_exception = true
    threads = []
    threads << Thread.new { check_feet(@feet_path) }
    threads << Thread.new { check_voice(@voice_path) }
    threads << Thread.new { check_device(@keyboard_id, @mouse_id) }
    threads << Thread.new { check_slack_call }
    threads << Thread.new { overall_activity }
    threads.each(&:join)
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

  def activity_exceeded?(part)
    time = Time.now.to_i
    unless @testing
      puts "active: #{@state[part][:active?]}"
      puts "#{part}-time active: #{time - @state[part][:activity_start]}"
    end
    @state[part][:active?] &&
      time - @state[part][:activity_start] > @state[part][:max_exertion] &&
      time > @state[part][:last_activity]
  end

  def check_feet(feet_path)
    File::Tail::Logfile.tail(feet_path, backward: 1, interval: TAIL_INTERVAL) do |_line|
      check(:feet)
    end
  end

  def check_voice(voice_path)
    File::Tail::Logfile.tail(voice_path, backward: 1, interval: TAIL_INTERVAL) do |_line|
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

  def check(part)
    @semaphore.synchronize do
      time = Time.now.to_i
      next if time < @pause_until

      @state[part][:last_activity] = time if @state[part][:last_activity].nil?

      if time - @state[part][:last_activity] < @state[part][:min_rest]
        unless @state[part][:active?]
          @state[part][:activity_start] = @state[part][:last_activity]
        end
        @state[part][:active?] = true
      else
        @state[part][:active?] = false
        @state[part][:activity_start] = time
      end

      if activity_exceeded?(part)
        warn("You should give your #{part} a break, wait #{@state[part][:min_rest]} seconds")
        rest_timer(@state[part][:min_rest], part)
      end

      @state[part][:last_activity] = time
    end
  end

  def check_slack_call
    @call_started = nil
    @call_ended = nil
    @last_warning = nil
    @last_call_duration = 0
    while @running
      call_logic
      sleep SLACK_CALL_INTERVAL
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
    if @call_ended && !slack_call && (@call_ended + SLACK_REST_TIME) <= Time.now.to_i
      @last_warning = nil
      @call_ended = nil
      @last_call_duration = 0
    end

    # warn if current call, or current plus last call is longer than 45 min
    if @call_started && Time.now.to_i - @call_started >= SLACK_CALL_LIMIT || @call_started && @last_call_duration && (Time.now.to_i - @call_started + @last_call_duration) >= SLACK_CALL_LIMIT
      if @last_warning && (Time.now.to_i - @last_warning < SLACK_WARNING_SNOOZE)
        return
      end

      warn('You have been on a call for over 45 minutes, take a 10 minute break')
      rest_timer(SLACK_REST_TIME, 'slack_call')
      @last_warning = Time.now.to_i
    end
  end

  def overall_activity
    @time_active = nil
    @stretch_timer = nil
    while @running
      overall_activity_logic
      stretch_logic

      sleep 1
    end
  end

  def overall_activity_logic
    time = Time.now.to_i
    return if @time_active && time - @time_active < OVERALL_ACTIVITY_INTERVAL

    feet_active = was_active?(@state[:feet][:last_activity], time)
    hands_active = was_active?(@state[:hands][:last_activity], time)
    voice_active = was_active?(@state[:voice][:last_activity], time)
    call_active = @call_active.nil? ? false : @call_active

    if feet_active || hands_active || voice_active || call_active
      @time_active = Time.now.to_i if @time_active.nil?
      @stretch_timer = Time.now.to_i if @stretch_timer.nil?
    else
      @time_active = nil
      @stretch_timer = nil
    end

    if @time_active && time - @time_active >= OVERALL_ACTIVITY_LIMIT
      if @last_oa_warning && Time.now - @last_oa_warning < OVERALL_ACTIVITY_WARNING_SNOOZE
        return
      end

      messg = "You have been fairly active for #{(time - @time_active) / 60} minutes, take a ten minute break"
      warn(messg)
      @last_oa_warning = Time.now
    end

    profile_reminder
  end

  def profile_reminder
    time = Time.now.to_i
    feet = @state[:feet][:last_activity]
    hands = @state[:hands][:last_activity]
    voice = @state[:voice][:last_activity]
    if (!feet.nil? && feet + 3600 < time) ||
      (!hands.nil? && hands + 3600 < time) ||
      (!voice.nil? && hands + 3600 < time)
        @inactive_for_hour = true
    end

    if @inactive_for_hour &&
      time - @time_active > 5.minutes &&
      (@state[:feet][:active?] ||
      @state[:hands][:active?] ||
      @state[:voice][:active?])
        warn( "You have resumed after a period of inactivity, is settings profile [#{state[:profile]}] still correct?")
        @inactive_for_hour = false
    end
  end

  def stretch_logic
    if @stretch_timer && Time.now.to_i - @stretch_timer >= STRETCH_TIME
      warn("You've been active for 15 minutes, stretch for a bit")
      @stretch_timer = Time.now.to_i
    end
  end

  private

  def was_active?(bodypart_last_active, time)
    bodypart_last_active.nil? ? false : time - bodypart_last_active <= OVERALL_ACTIVITY_INTERVAL
  end

  def rest_timer(time, activity)
    message = "#{activity}-break over"
    return if @testing

    pid = Process.fork do
      sleep time
      `paplay --volume 30000 ./sounds/service-login.ogg`
      `xmessage #{message} -center -timeout 2`
    end
    Process.detach(pid)
  end

  def slack_call_found?
    xids = `xdotool search --class --classname --name slack`.split("\n")
    return false if $CHILD_STATUS.exitstatus > 0

    xids.find do |xid|
      !`xwininfo -all -id "#{xid}"| grep "Slack call with"`.strip.empty?
    end
  end

  def warn(reason)
    if @testing
      message = "#{Time.now} - #{reason}\n"
      @warn_log << message
    elsif Time.now.to_i > @pause_until
      `paplay --volume 30000 ./sounds/when.ogg`
      @pause_until = Time.now.to_i + 2
      sleep 1
      pid = Process.fork do
        `xmessage #{Shellwords.escape(reason)} -center -timeout 3`
      end
      Process.detach(pid)
      File.open('testlog', 'a') { |f| f << "#{reason}\n" }
    end
  end
end
