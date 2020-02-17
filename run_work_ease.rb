#! /usr/bin/env ruby

require './work_ease.rb'

bodypart_activity = {
  feet: { last_activity: nil,
          activity_level: 0,
          min_rest: 60,
          max_exertion: 600,
          high_activity_start: nil },
  hands: { last_activity: nil,
           min_rest: 5,
           activity_level: 0,
           max_exertion: 10,
           high_activity_start: nil },
  voice: { last_activity: nil,
           min_rest: 10,
           activity_level: 0,
           max_exertion: 120,
           high_activity_start: nil }
}

keyboard_id, mouse_id = WorkEase.find_device_ids(keyboard_name: 'AT Translated Set 2 keyboard', mouse_name: 'SynPS/2 Synaptics TouchPad')
WorkEase.new.start(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity, feet_path: "#{ENV['HOME']}/code/midityper/log", voice_path: "#{ENV['HOME']}/code/speech/log")
