require 'rails_helper'

# IA entende a conversa F1: com `papeis: true` (só a IA de assunto, com a flag), cada linha diz a hora e quem falou.
# A hora sai no fuso padrão do CRM (America/Sao_Paulo) quando nem o contato nem a conta dizem outro.
RSpec.describe Autonomia::Decisores::Estado do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Cliente') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:nosso_robo) { create(:agent_bot, account: account) }
  let(:robo_de_fora) { create(:agent_bot, account: account) }
  let(:leituras) { %w[mensagens_com_respostas] }

  before do
    Autonomia::Agents::AgentInbox.create!(account: account, inbox: inbox, agent_bot: nosso_robo,
                                          agent: Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'sdr'))
  end

  def falar(conteudo, tipo, sender, momento)
    travel_to(momento) do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: tipo, content: conteudo, sender: sender)
    end
  end

  def conversa
    t0 = Time.zone.parse('2026-10-14 13:00 UTC')
    falar('Quero um orçamento', :incoming, contact, t0)
    falar('Escolha uma opção', :outgoing, nosso_robo, t0 + 1.minute)
    falar('Mensagem automática', :outgoing, robo_de_fora, t0 + 2.minutes)
    falar('Te respondo já', :outgoing, admin, t0 + 3.minutes)
    falar('A segunda opção', :incoming, contact, t0 + 4.minutes)
  end

  it 'com papeis, a hora local e quem falou, em vez de Customer/Team' do
    ultima = conversa
    lido = described_class.new(conversation: conversation, message: ultima, leituras: leituras, papeis: true).conversa[:messages]

    expect(lido).to eq(['[10:00] Customer: Quero um orçamento', '[10:01] Our assistant (AI): Escolha uma opção',
                        '[10:02] Automatic message (other system): Mensagem automática', '[10:03] Team member: Te respondo já',
                        '[10:04] Customer: A segunda opção'])
  end

  it 'com papeis, o envio que falhou não chegou ao cliente e sai' do
    ultima = conversa
    conversation.messages.find_by(content: 'Te respondo já').update!(status: :failed)
    lido = described_class.new(conversation: conversation, message: ultima, leituras: leituras, papeis: true).conversa[:messages]

    expect(lido.join("\n")).not_to include('Te respondo já')
  end

  it 'sem papeis, a saída de sempre' do
    ultima = conversa
    lido = described_class.new(conversation: conversation, message: ultima, leituras: leituras).conversa[:messages]

    expect(lido).to eq(['Customer: Quero um orçamento', 'Team: Escolha uma opção', 'Team: Mensagem automática',
                        'Team: Te respondo já', 'Customer: A segunda opção'])
  end
end
