require './work_ease'

$inputs = %w[feet keyboard mouse voice]

def clean_logs
  $inputs.each { |file| File.truncate("inputs/#{file}", 0) }
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

clean_logs
workease_thread = Thread.new { WorkEase.new.start }

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
