#! /usr/bin/env ruby
# frozen_string_literal: true

require_relative '../workease'
require 'active_support/time'
require 'timecop'

bodypart_activity = {
  feet: { last_activity: nil,
          active?: false,
          min_rest: 5,
          max_exertion: 19,
          activity_start: nil },
  hands: { last_activity: nil,
           min_rest: 5,
           active?: false,
           max_exertion: 10,
           activity_start: nil },
  voice: { last_activity: nil,
           min_rest: 10,
           active?: false,
           max_exertion: 20,
           activity_start: nil }
}

keyboard_id, mouse_id = WorkEase.find_device_ids(keyboard_name: 'VirtualBox USB Keyboard', mouse_name: 'VirtualBox mouse integration')

RSpec.describe WorkEase do
  before(:each) do
    @w = WorkEase.new(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity, feet_path: '../inputs/feet', voice_path: '../inputs/voice')
    @w.testing = true
    @time = Time.at(1_591_192_757)
  end

  after(:each) do
    Timecop.return
  end

  def set_time(number)
    Timecop.freeze(@time + number)
  end

  def simulate_activity(part, times)
    times.each do |t|
      set_time(t)
      @w.check(part)
      @w.overall_activity_logic
    end
  end

  def call_check(time)
    set_time(time)
    @w.call_logic
  end

  describe '#start' do
    it 'starts threads running all checks' do
      expect(@w).to receive(:check_feet)
      expect(@w).to receive(:check_voice)
      expect(@w).to receive(:check_device)
      expect(@w).to receive(:check_slack_call)
      expect(@w).to receive(:overall_activity)
      @w.start
    end
  end

  describe '#activity_exceeded?' do
    it 'returns false if bodypart has not been too active' do
      set_time(0)
      exertion_limit = @w.state[:voice][:max_exertion]
      @w.state[:voice][:active?] = true
      @w.state[:voice][:activity_start] = @time.to_i - exertion_limit - 1
      @w.state[:voice][:last_activity] = @time.to_i

      result = @w.activity_exceeded?(:voice)
      expect(result).to eq(false)
    end

    it 'returns true if bodypart has been too active' do
      exertion_limit = @w.state[:voice][:max_exertion]
      @w.state[:voice][:active?] = true
      @w.state[:voice][:activity_start] = @time.to_i - exertion_limit
      @w.state[:voice][:last_activity] = @time.to_i

      result = @w.activity_exceeded?(:voice)
      expect(result).to eq(true)
    end
  end

  describe '#check' do
    it 'sends a warning if bodypart has been too active' do
      # simulate 5 feet actions with 3 second intervals
      (0..5).each { |n| set_time(n * 4.seconds); @w.check(:feet) }

      fixture = ["2020-06-03 15:59:37 +0200 - You should give your feet a break, wait 5 seconds\n"]
      expect(@w.warn_log).to eq(fixture)
    end
  end

  describe '#call_logic' do
    it 'sends a warning if a slack call takes more than 45 minutes' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      call_check(0)
      call_check(45.minutes + 1)

      fixture = ["2020-06-03 16:44:18 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end

    it 'also warns if two calls together take more than 45 minutes without a 10 min break' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      call_check(0)
      allow(@w).to receive(:slack_call_found?).and_return(false)
      call_check(25.minutes) # 1st call ended after 25 minutes
      allow(@w).to receive(:slack_call_found?).and_return(true)
      call_check(34.minutes) # 2nd call started after 9 minute break
      call_check(54.minutes) # 45 minutes total

      fixture = ["2020-06-03 16:53:17 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end

    it 'does not warn if a call take less than 45 minutes' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      call_check(0)
      call_check(44.minutes + 59)

      fixture = []
      expect(@w.warn_log).to eq(fixture)
    end

    it 'does not warn if two calls take more than 45 minutes if there was a 10 min break' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      call_check(0)
      allow(@w).to receive(:slack_call_found?).and_return(false)
      call_check(25.minutes) # 1st call ended after 25 minutes
      call_check(35.minutes) # the method call_logic is usually called in a loop, this gives it a chance to reset its timers
      allow(@w).to receive(:slack_call_found?).and_return(true)
      call_check(36.minutes) # 2nd call started after 11 minute break
      call_check(60.minutes) # 49 minutes total

      fixture = []
      expect(@w.warn_log).to eq(fixture)
    end

    it 'keeps sending warnings every 5 minutes afer a call lasted more than 45 min' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      [0, 45, 50, 55].each { |n| call_check(n.minutes) }

      fixture = ["2020-06-03 16:44:17 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n",
                 "2020-06-03 16:49:17 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n",
                 "2020-06-03 16:54:17 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end
  end

  describe '#overall_activity_logic' do
    it 'sends a warning if overall activity has been high for 50 minutes, without 3 minutes of total inactivity' do
      # one action every 3 minutes for 50 minutes
      simulate_activity(:hands, (0..17).to_a.map { |n| n * 3.minutes })

      fixture = ["2020-06-03 16:50:17 +0200 - You have been fairly active for 51 minutes, take a ten minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end

    it 'does not warn if there is a 3 minute full break' do
      # 45 minutes of activity
      simulate_activity(:hands, (0..15).to_a.map { |n| n * 3.minutes })

      set_time(2881) # let oa logic reset @time_active, 3min, 1 sec since last action
      @w.overall_activity_logic
      simulate_activity(:hands, [2940]) # use hands 4 minutes after last action
      simulate_activity(:hands, [3060]) # again use hands 2 minutes after last action

      fixture = []
      expect(@w.warn_log).to eq(fixture)
    end

    it 'sends a warning every 5 minutes after 50 minutes of overall activity' do
      # one action every 3 minutes for 63 minutes
      simulate_activity(:hands, (0..21).to_a.map { |n| n * 3.minutes })

      fixture = ["2020-06-03 16:50:17 +0200 - You have been fairly active for 51 minutes, take a ten minute break\n",
                 "2020-06-03 16:56:17 +0200 - You have been fairly active for 57 minutes, take a ten minute break\n",
                 "2020-06-03 17:02:17 +0200 - You have been fairly active for 63 minutes, take a ten minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end
  end

  describe '#stretch_logic' do
    it 'warns to stretch after 15 minutes of overall activity' do
      simulate_activity(:hands, (0..6).to_a.map { |n| n * 3.minutes })

      @w.stretch_logic
      fixture = ["2020-06-03 16:17:17 +0200 - You've been active for 15 minutes, stretch for a bit\n"]
      expect(@w.warn_log).to eq(fixture)
    end

    it 'does not warn after 15 min if there was a 3 minute full break' do
      # 12 minutes of simulated activity
      simulate_activity(:hands, (0..4).to_a.map { |n| n * 3.minutes })

      set_time(901) # 3 minutes, 1 sec after last action reset @last_active
      @w.overall_activity_logic
      simulate_activity(:hands, [930]) # 3.5 minutes after last action
      simulate_activity(:hands, [1080]) # 18 minutes of activity, with 3.5 minute break

      fixture = []
      expect(@w.warn_log).to eq(fixture)
    end
  end

  describe '@semaphore' do
    it 'locks mutex when in check method' do
      expect(@w.semaphore).to receive(:synchronize)
      @w.check(:hands)
    end
  end
end
