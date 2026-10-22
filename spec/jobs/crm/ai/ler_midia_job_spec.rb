require 'rails_helper'

RSpec.describe Crm::Ai::LerMidiaJob do
  let(:message) { create(:message) }
  let(:leitor) { instance_double(Crm::Ai::LeitorDeMidia, perform: 1) }

  before { allow(Crm::Ai::LeitorDeMidia).to receive(:new).and_return(leitor) }

  it 'lê os anexos da mensagem', :aggregate_failures do
    described_class.perform_now(message.id)

    expect(Crm::Ai::LeitorDeMidia).to have_received(:new).with(message)
    expect(leitor).to have_received(:perform)
  end

  it 'mensagem que sumiu: não faz nada' do
    described_class.perform_now(0)

    expect(Crm::Ai::LeitorDeMidia).not_to have_received(:new)
  end

  it 'vai na fila high' do
    expect(described_class.new.queue_name).to eq('high')
  end
end
