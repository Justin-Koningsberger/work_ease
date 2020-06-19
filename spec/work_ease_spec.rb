#! /usr/bin/env ruby
# frozen_string_literal: true

require_relative '../workease2'
require 'timecop'

bodypart_activity = {
  feet: { last_activity: nil,
          activity_level: 0,
          min_rest: 5,
          max_exertion: 19,
          high_activity_start: nil },
  hands: { last_activity: nil,
           min_rest: 5,
           activity_level: 0,
           max_exertion: 10,
           high_activity_start: nil },
  voice: { last_activity: nil,
           min_rest: 10,
           activity_level: 0,
           max_exertion: 20,
           high_activity_start: nil }
}

keyboard_id, mouse_id = WorkEase.find_device_ids(keyboard_name: 'VirtualBox USB Keyboard', mouse_name: 'VirtualBox mouse integration')

RSpec.describe WorkEase do
  before(:each) do
    @w = WorkEase.new(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity, feet_path: '../inputs/feet', voice_path: '../inputs/voice')
    @w.testing = true
    @time = Time.at(1591192757)
  end

  after(:each) do
    Timecop.return
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
      Timecop.freeze(@time)
      @w.bodypart[:voice][:activity_level] = 1
      @w.bodypart[:voice][:high_activity_start] = @time.to_i - 19
      @w.bodypart[:voice][:last_activity] = @time.to_i

      var = @w.activity_exceeded?(:voice)
      expect(var).to eq(false)
    end

    it 'returns true if bodypart has been too active' do
      @w.bodypart[:voice][:activity_level] = 1
      @w.bodypart[:voice][:high_activity_start] = @time.to_i - 20
      @w.bodypart[:voice][:last_activity] = @time.to_i

      var = @w.activity_exceeded?(:voice)
      expect(var).to eq(true)
    end
  end

  describe '#check' do
    it 'sends a warning if bodypart has been too active' do

      Timecop.freeze(@time)
      @w.check(:feet)
      Timecop.freeze(@time + 4)
      @w.check(:feet)
      Timecop.freeze(@time + 8)
      @w.check(:feet) #8 seconds
      Timecop.freeze(@time + 12)
      @w.check(:feet)
      Timecop.freeze(@time + 16)
      @w.check(:feet)
      Timecop.freeze(@time + 20)
      @w.check(:feet) #20 seconds, should warn now

      fixture =  ["2020-06-03 15:59:37 +0200 - You should give your feet a break, wait 5 seconds\n"]
      expect(@w.warn_log).to eq(fixture)
    end
  end

  describe '#call_logic' do
    it 'sends a warning if a slack call takes more than 45 minutes' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      Timecop.freeze(@time)
      @w.call_logic
      Timecop.freeze(@time + 2701)
      @w.call_logic

      fixture = ["2020-06-03 16:44:18 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end

    it 'also warns if two calls together take more than 45 minutes without a 10 min break' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      Timecop.freeze(@time)
      @w.call_logic
      allow(@w).to receive(:slack_call_found?).and_return(false)
      Timecop.freeze(@time + 25 * 60) # 1st call ended after 25 minutes
      @w.call_logic
      allow(@w).to receive(:slack_call_found?).and_return(true)
      Timecop.freeze(@time + 34 * 60) # 2nd call started after 9 minute break
      @w.call_logic
      Timecop.freeze(@time + 54 * 60) # 45 minutes total
      @w.call_logic

      fixture = ["2020-06-03 16:53:17 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end

    it 'does not warn if a call take less than 45 minutes' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      Timecop.freeze(@time)
      @w.call_logic
      Timecop.freeze(@time + 2699)
      @w.call_logic

      fixture = []
      expect(@w.warn_log).to eq(fixture)
    end

    it 'does not warn if two calls take more than 45 minutes if there was a 10 min break' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      Timecop.freeze(@time)
      @w.call_logic
      allow(@w).to receive(:slack_call_found?).and_return(false)
      Timecop.freeze(@time + 25 * 60) # 1st call ended after 25 minutes
      @w.call_logic
      Timecop.freeze(@time + 35 * 60) # the method call_logic is usually called in a loop,
      @w.call_logic # this gives it a chance to reset its timers
      allow(@w).to receive(:slack_call_found?).and_return(true)
      Timecop.freeze(@time + 36 * 60) # 2nd call started after 11 minute break
      @w.call_logic
      Timecop.freeze(@time + 60 * 60) # 49 minutes total
      @w.call_logic

      fixture = []
      expect(@w.warn_log).to eq(fixture)
    end

    it 'keeps sending warnings every 5 minutes afer a call lasted more than 45 min' do
      allow(@w).to receive(:slack_call_found?).and_return(true)
      Timecop.freeze(@time)
      @w.call_logic
      Timecop.freeze(@time + 45 * 60)
      @w.call_logic
      Timecop.freeze(@time + 50 * 60)
      @w.call_logic
      Timecop.freeze(@time + 55 * 60)
      @w.call_logic

      fixture = ["2020-06-03 16:44:17 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n",
       "2020-06-03 16:49:17 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n",
       "2020-06-03 16:54:17 +0200 - You have been on a call for over 45 minutes, take a 10 minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end
  end

  describe '#overall_activity_logic' do
    it 'sends a warning if overall activity has been high for 50 minutes, without 3 minutes of total inactivity' do
      @w.interval = 3 * 60
      times = []
      for i in (0..17)
        times << i * 180
      end

      # one action every 3 minutes for 50 minutes
      times.each do |t|
        time = @time + t
        Timecop.freeze(time)
        @w.check(:hands)
        @w.overall_activity_logic
      end

      fixture = ["2020-06-03 16:50:17 +0200 - You have been fairly active for 51 minutes, take a ten minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end

    it 'does not warn if there is a 3 minute full break' do
      @w.interval = 3 * 60
      times = [0, 180, 360, 540, 720, 900, 1080, 1260, 1440, 1620, 1800, 1980, 2160, 2340, 2520, 2700]

      # 45 minutes of activity
      times.each do |t|
        time = @time + t
        Timecop.freeze(time)
        @w.check(:hands)
        @w.overall_activity_logic
      end

      Timecop.freeze(@time + 2881) # let oa logic reset @time_active, 3min, 1 sec since last action
      @w.overall_activity_logic
      Timecop.freeze(@time + 2940) # use hands 4 minutes after last action
      @w.check(:hands)
      @w.overall_activity_logic
      Timecop.freeze(@time + 3060) # again use hands 2 minutes after last action
      @w.check(:hands)
      @w.overall_activity_logic

      fixture = []
      expect(@w.warn_log).to eq(fixture)
    end

    it 'sends a warning every 5 minutes after 50 minutes of overall activity' do
      @w.interval = 3 * 60
      times = []
      for i in (0..21)
        times << i * 180
      end

      # one action every 3 minutes for 63 minutes
      times.each do |t|
        time = @time + t
        Timecop.freeze(time)
        @w.check(:hands)
        @w.overall_activity_logic
      end

      fixture = ["2020-06-03 16:50:17 +0200 - You have been fairly active for 51 minutes, take a ten minute break\n",
       "2020-06-03 16:56:17 +0200 - You have been fairly active for 57 minutes, take a ten minute break\n",
       "2020-06-03 17:02:17 +0200 - You have been fairly active for 63 minutes, take a ten minute break\n"]
      expect(@w.warn_log).to eq(fixture)
    end
  end

  describe '#stretch_logic' do
    it 'warns to stretch after 15 minutes of overall activity' do
      times = [0, 180, 360, 540, 720, 900, 1080]

      times.each do |t|
        time = @time + t
        Timecop.freeze(time)
        @w.check(:hands)
        @w.overall_activity_logic
      end

      @w.stretch_logic
      fixture = ["2020-06-03 16:17:17 +0200 - You've been active for 15 minutes, stretch for a bit\n"]
      expect(@w.warn_log).to eq(fixture)
    end

    it 'does not warn after 15 min if there was a 3 minute full break' do
      times = [0, 180, 360, 540, 720] # 900, 1080

      times.each do |t|
        time = @time + t
        Timecop.freeze(time)
        @w.check(:hands)
        @w.overall_activity_logic
      end

      Timecop.freeze(@time + 901) # 3 minutes, 1 sec after last action reset @last_active
      @w.overall_activity_logic
      Timecop.freeze(@time + 930)
      @w.check(:hands)
      @w.overall_activity_logic
      Timecop.freeze(@time + 1080)
      @w.overall_activity_logic
      @w.stretch_logic

      fixture = []
      expect(@w.warn_log).to eq(fixture)
    end
  end
end
