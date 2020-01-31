require './work_ease'

@inputs = %w[feet keyboard mouse voice]

def clean_logs
  @inputs.each { |file| File.truncate("inputs/#{file}", 0) }
  File.truncate('testlog', 0)
end

def log(file:, text:)
  File.open('testlog', 'a') do |f|
    f << "#{file} - #{Time.now} - #{text}\n"
    puts "#{file} - #{Time.now} - #{text}\n"
  end
end

def simulate_keyboard(key)
  `xdotool key #{key}`
end

def simulate_mouse
  `xdotool mousemove_relative 5 5`
end

bodypart_activity = {
  feet: { last_activity: nil,
          activity_level: 0,
          min_rest: 5, # 60
          max_exertion: 50, # 600
          high_activity_start: nil },
  hands: { last_activity: nil,
           min_rest: 10,
           activity_level: 0,
           max_exertion: 20, # 120
           high_activity_start: nil },
  voice: { last_activity: nil,
           min_rest: 10,
           activity_level: 0,
           max_exertion: 20, # 120
           high_activity_start: nil }
}

clean_logs
keyboard_id, mouse_id = WorkEase.find_device_ids(keyboard_name: 'Virtual core XTEST keyboard', mouse_name: 'Virtual core XTEST pointer')

workease_thread = Thread.new { WorkEase.new.start(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity) }

key = 'space'

10.times do
  log(file: 'keyboard', text: "#{key} pressed")
  simulate_keyboard(key)
  sleep 3
end

sleep 12

10.times do
  log(file: 'mouse', text: 'mouse movement')
  simulate_mouse
  sleep 3
end

workease_thread.join
