#! /usr/bin/env ruby
# frozen_string_literal: true

require_relative 'workease.rb'

bodypart_activity = {
  feet: { last_activity: nil,
          active?: false,
          min_rest: 60,
          max_exertion: 600,
          activity_start: nil },
  hands: { last_activity: nil,
           min_rest: 5,
           active?: false,
           max_exertion: 10,
           activity_start: nil },
  voice: { last_activity: nil,
           min_rest: 30,
           active?: false,
           max_exertion: 120,
           activity_start: nil }
}

keyboard_id, mouse_id = WorkEase.find_device_ids(keyboard_name: 'AT Translated Set 2 keyboard', mouse_name: 'SynPS/2 Synaptics TouchPad')

WorkEase.new(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity, feet_path: "#{ENV['HOME']}/code/midityper/log", voice_path: "#{ENV['HOME']}/code/speech/log").start
