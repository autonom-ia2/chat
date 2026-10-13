require 'rails_helper'

RSpec.describe Whatsapp::Templates::WebhookJob do
  let(:changes) do
    [{ 'waba_id' => '1', 'time' => 10, 'field' => 'message_template_status_update', 'value' => { 'event' => 'APPROVED' } },
     { 'waba_id' => '2', 'time' => 11, 'field' => 'template_category_update', 'value' => { 'new_category' => 'UTILITY' } }]
  end

  it 'fila default (não espera a fila low das campanhas)' do
    expect(described_class.new.queue_name).to eq('default')
  end

  it 'aplica cada aviso, na ordem em que chegou' do
    events = changes.map { instance_double(Whatsapp::Templates::WebhookEvent, perform: nil) }
    allow(Whatsapp::Templates::WebhookEvent).to receive(:new).and_return(*events)

    described_class.perform_now(changes)

    expect(Whatsapp::Templates::WebhookEvent).to have_received(:new)
      .with(waba_id: '1', time: 10, field: 'message_template_status_update', value: { 'event' => 'APPROVED' }).ordered
    expect(Whatsapp::Templates::WebhookEvent).to have_received(:new)
      .with(waba_id: '2', time: 11, field: 'template_category_update', value: { 'new_category' => 'UTILITY' }).ordered
    expect(events).to all(have_received(:perform))
  end
end
