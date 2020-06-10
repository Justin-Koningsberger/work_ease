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
    @w = WorkEase.new
    @w.testing = true
    @time = Time.at(1591192757)
  end

  after(:each) do
    Timecop.return
  end

  describe '#start' do
    it 'calls check_inputs with some args' do
      expect(@w).to receive(:check_inputs).with(keyboard_id, mouse_id, '../inputs/feet', '../inputs/voice')
      @w.start(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity, feet_path: '../inputs/feet', voice_path: '../inputs/voice')
    end
  end

  describe '#check_inputs' do
    it 'starts threads running all checks' do
      expect(@w).to receive(:check_feet)
      expect(@w).to receive(:check_voice)
      expect(@w).to receive(:check_device)
      expect(@w).to receive(:check_slack_call)
      # expect(@w).to receive(:overall_activity)
      @w.check_inputs(keyboard_id, mouse_id, '../inputs/feet', '../inputs/voice')
    end
  end

  describe '#activity_exceeded?' do
    it 'returns false if bodypart has not been too active' do
      Timecop.freeze(@time)
      bodypart_activity[:voice][:activity_level] = 1
      bodypart_activity[:voice][:high_activity_start] = @time.to_i - 19
      bodypart_activity[:voice][:last_activity] = @time.to_i
      @w.bodypart = bodypart_activity

      var = @w.activity_exceeded?(:voice)
      expect(var).to eq(false)
    end

    it 'returns true if bodypart has been too active' do
      bodypart_activity[:voice][:activity_level] = 1
      bodypart_activity[:voice][:high_activity_start] = @time.to_i - 20
      bodypart_activity[:voice][:last_activity] = @time.to_i
      @w.bodypart = bodypart_activity

      var = @w.activity_exceeded?(:voice)
      expect(var).to eq(true)
    end
  end

  describe '#check' do
    it 'sends a warning if bodypart has been too active' do
      @w.bodypart = bodypart_activity

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
      Timecop.freeze(@time + 35 * 60) # the method call_logic is usally called in a loop,
      @w.call_logic # this gives it a chance to reset it's timers
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
end
