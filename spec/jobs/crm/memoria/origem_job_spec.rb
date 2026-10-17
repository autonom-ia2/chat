require 'rails_helper'

RSpec.describe Crm::Memoria::OrigemJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { mensagem!(conversation, :incoming, content: 'oi') }

  it 'grava a autoria com a flag; sem ela, ou na caixa tirada da memória, não grava' do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    expect { described_class.perform_now(message.id) }.not_to change(Crm::MensagemOrigem, :count)

    ligar_memoria!(account)
    Crm::MemoriaConfig.create!(account: account, caixas_excluidas: [conversation.inbox_id])
    expect { described_class.perform_now(message.id) }.not_to change(Crm::MensagemOrigem, :count)

    Crm::MemoriaConfig.find_by(account_id: account.id).update!(caixas_excluidas: [])
    expect { described_class.perform_now(message.id) }.to change(Crm::MensagemOrigem, :count).by(1)
  end
end
