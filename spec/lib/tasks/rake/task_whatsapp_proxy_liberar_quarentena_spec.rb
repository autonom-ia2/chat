require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['autonomia:whatsapp_proxy:liberar_quarentena'] }

  before do
    Rails.application.load_tasks unless described_class.task_defined?('autonomia:whatsapp_proxy:liberar_quarentena')
    task.reenable
  end

  it 'takes the IP out of quarantine before the 24 h, so it can be assigned again' do
    WhatsappProxy::Quarantine.put!('10.0.0.1', 'isp', 'teste')
    WhatsappProxy::Quarantine.put!('10.0.0.2', 'isp', 'teste')

    expect { task.invoke('10.0.0.1') }.to output(/liberados=1/).to_stdout

    expect(WhatsappProxy::Quarantine.addresses).to eq(['10.0.0.2'])
  end

  it 'lets the quarantine expire on its own after 24 h' do
    WhatsappProxy::Quarantine.put!('10.0.0.1', 'isp', 'teste')

    travel_to(25.hours.from_now) { expect(WhatsappProxy::Quarantine.addresses).to be_empty }
  end
end
