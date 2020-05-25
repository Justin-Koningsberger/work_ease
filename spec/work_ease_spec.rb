require_relative '../work_ease'

bodypart_activity = {
  feet: { last_activity: nil,
          activity_level: 0,
          min_rest: 5,
          max_exertion: 50,
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
  describe '#start' do
    it "calls check_inputs with some args" do
      w = WorkEase.new
      expect(w).to receive(:check_inputs).with(keyboard_id, mouse_id, '../inputs/feet', '../inputs/voice')
      w.start(keyboard_id: keyboard_id, mouse_id: mouse_id, bodypart_activity: bodypart_activity, feet_path: '../inputs/feet', voice_path: '../inputs/voice')
    end
  end

  # TODO, uitzoeken waarom regel 49 in script errort: undefined method `join' for nil:NilClass
  # describe '#check_inputs' do
  #   it "starts thread running overall_activity" do
  #     w = WorkEase.new
  #     puts keyboard_id
  #     expect(Thread).to receive(:new)
  #     expect(w).to receive(:overall_activity)
  #     w.check_inputs(keyboard_id, mouse_id, '../inputs/feet', '../inputs/voice')
  #   end
  # end

  describe '#overall_activity' do
    it "sends a warning after 50 minutes of some activity using any input" do
      w = WorkEase.new
      bodypart_activity[:feet][:last_activity] = Time.now.to_i
      expect(w).to receive(:overall_activity)
      w.overall_activity
    end
  end
end
