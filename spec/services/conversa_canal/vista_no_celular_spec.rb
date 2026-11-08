require 'rails_helper'

# #2246: o "visto" da leitura no celular vai até o fim do segundo da mensagem lida e nunca volta.
RSpec.describe ConversaCanal::VistaNoCelular do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:inicio) { Time.zone.parse('2026-10-27 10:00:00') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, agent_last_seen_at: inicio - 1.hour) }

  before { allow(OnlineStatusTracker).to receive(:get_available_users).and_return({}) }

  def mensagem(segundos, tipo = :incoming)
    travel_to(inicio + segundos) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo)
    end
  end

  it 'marca como lidas a mensagem e as do mesmo segundo, não as de depois' do
    lida = mensagem(0.2)
    mensagem(0.7)
    mensagem(1)

    expect(described_class.marcar!(lida)).to be(true)
    expect(conversation.reload.unread_incoming_messages.count).to eq(1)
  end

  it 'não anda nem avisa quando o visto já passou da mensagem' do
    lida = mensagem(0)
    conversation.update_columns(agent_last_seen_at: inicio - 1.second) # rubocop:disable Rails/SkipsModelValidations
    lida.update_columns(created_at: inicio - 2.seconds) # rubocop:disable Rails/SkipsModelValidations
    expect(ConversaCanal::VistaAoResponder).not_to receive(:avisar)

    expect(described_class.marcar!(lida.reload)).to be(false)
  end

  it 'ignora mensagem que não é do cliente' do
    expect(described_class.marcar!(mensagem(0, :outgoing))).to be(false)
  end

  it 'liga e desliga pela flag da conta' do
    expect(described_class.enabled?(account)).to be(false)

    account.enable_features!(described_class::FLAG)

    expect(described_class.enabled?(account)).to be(true)
  end
end
