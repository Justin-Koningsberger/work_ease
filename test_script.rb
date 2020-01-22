require './work_ease'

$inputs = %w[feet keyboard mouse voice]
@actions = 0
@started_at = Time.now.to_i

def clean_logs
  $inputs.each { |file| File.truncate("inputs/#{file}", 0) }
  File.truncate('testlog', 0)
end

def log(file:, text:)
  File.open("inputs/#{file}", 'a') do |f|
    f << "#{Time.now} - #{text}\n"
  end

  File.open('testlog', 'a') do |f|
    f << "#{file} - #{Time.now} - #{text}\n"
    puts "#{file} - #{Time.now} - #{text}"
  end
end

def simulate_activity
  input = $inputs[rand(4)]
  log(file: input, text: "action #{@actions += 1}")
  sleep(rand(1..2))
end

clean_logs
workease_thread = Thread.new { WorkEase.new.start }

# loop do
#   simulate_activity
# end

loop do
  log(file: $inputs[ARGV[0].to_i], text: 'testing')
  sleep rand(1..3)
end

# 5.times do
#   log(file: $inputs[ARGV[0].to_i], text: 'testing2')
#   sleep rand(11..13)
# end

workease_thread.join
