require 'rails_helper'

# #1367 (alavanca 0): o Testar roda por aqui; a espera na fila entra no log estruturado, sem conteúdo.
RSpec.describe Crm::Ai::InteractiveJob do
  let(:request_id) { 'pedido-1' }

  before do
    data = { 'status' => 'pending', 'operation' => 'agent_test', 'inputs' => { 'message' => 'conteúdo do dono' } }
    allow(Crm::Ai::InteractiveRequest).to receive(:read).with(request_id).and_return(data)
    allow(Crm::Ai::InteractiveRequest).to receive(:claim).with(request_id).and_return(false)
    allow(Rails.logger).to receive(:info)
  end

  it 'logs the operation and how long the request waited in the queue' do
    freeze_time
    job = described_class.new(request_id)
    job.enqueued_at = 1.2.seconds.ago

    job.perform_now

    expect(Rails.logger).to have_received(:info)
      .with("[crm][ai][interactive] start request=#{request_id} operation=agent_test queue_wait_ms=1200")
    expect(Rails.logger).not_to have_received(:info).with(a_string_including('conteúdo do dono'))
  end

  it 'logs an empty wait when the job ran without going through the queue' do
    described_class.perform_now(request_id)

    expect(Rails.logger).to have_received(:info)
      .with("[crm][ai][interactive] start request=#{request_id} operation=agent_test queue_wait_ms=")
  end
end
