#! /usr/bin/env ruby
# frozen_string_literal: true

require_relative 'workease.rb'

bodypart_activity = {
  feet: { last_activity: nil,
          active?: false,
          min_rest: 5,
          max_exertion: 50,
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

WorkEase.new(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity, feet_path: 'inputs/feet', voice_path: 'inputs/voice').start
