#! /usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
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

if ARGV.empty?
  puts "Profile setting argument missing, -h for help, starting in standard profile."
end

OptionParser.new do |opts|
  opts.banner = 'Usage: ./test_script.rb [option], do not use more than 1 option, or they will override each other'

  opts.on('-1', '--profile-1', 'Barely any typing') do |_o|
    bodypart_activity[:hands][:min_rest] = 10
    bodypart_activity[:hands][:max_exertion] = 5
    bodypart_activity[:feet][:min_rest] = 3
    bodypart_activity[:feet][:max_exertion] = 70
    bodypart_activity[:voice][:min_rest] = 5
    bodypart_activity[:voice][:max_exertion] = 40
  end

  opts.on('-2', '--profile-2', 'Very limited voice activity') do |_o|
    # TODO
  end

  opts.on('-3', '--profile-3', 'Limit feet pedal activity') do |_o|
    # TODO
  end

  opts.on('-h', '--help', 'Show options') do
    puts opts
    exit
  end
end.parse!

keyboard_id, mouse_id = WorkEase.find_device_ids(keyboard_name: 'AT Translated Set 2 keyboard', mouse_name: 'SynPS/2 Synaptics TouchPad')

WorkEase.new(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity, feet_path: "#{ENV['HOME']}/code/midityper/log", voice_path: "#{ENV['HOME']}/code/speech/log").start
