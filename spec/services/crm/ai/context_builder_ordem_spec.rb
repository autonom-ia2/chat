require 'rails_helper'

# IA entende a conversa F1: com a flag, a avaliação de etapa lê a ordem (`after`) e desde quando o cliente espera.
RSpec.describe Crm::Ai::ContextBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Pedido', contact: contact,
                              primary_conversation: conversation, currency: 'BRL')
  end
  let(:nosso_robo) { create(:agent_bot, account: account) }

  before do
    Autonomia::Agents::AgentInbox.create!(account: account, inbox: inbox, agent_bot: nosso_robo,
                                          agent: Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'sdr'))
  end

  def falar(tipo, sender, momento)
    travel_to(momento) do
      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'texto', message_type: tipo, sender: sender)
    end
  end

  def montar_conversa
    t0 = 10.minutes.ago
    falar(:incoming, contact, t0)
    falar(:outgoing, nosso_robo, t0 + 1.minute)
    falar(:incoming, contact, t0 + 2.minutes)
    falar(:incoming, contact, t0 + 3.minutes)
  end

  def contexto(janela: :avaliacao) = described_class.new(card: card, janela: janela).perform

  context 'with the flag on' do
    before { account.enable_features!(Crm::Ai::FatosDaConversa::FLAG) }

    it 'a mensagem do cliente leva quem falou antes, e o estado diz desde quando ele espera', :aggregate_failures do
      ultima = montar_conversa
      mensagens = contexto[:recent_messages]

      expect(mensagens.map { |m| m[:after] }).to eq([nil, nil, 'platform_agent', 'customer'])
      expect(mensagens[1]).not_to have_key(:after)
      expect(contexto.dig(:conversation_state, :customer_waiting_since)).to eq((ultima.created_at - 1.minute).iso8601)
    end

    it 'com a última fala do atendimento, ninguém espera' do
      montar_conversa
      falar(:outgoing, admin, Time.current)

      expect(contexto[:conversation_state]).to include(customer_waiting_since: nil)
    end

    it 'os outros leitores (janela curta) não mudam', :aggregate_failures do
      montar_conversa

      expect(contexto(janela: :curta)[:recent_messages].first).not_to have_key(:after)
      expect(contexto(janela: :curta)[:conversation_state]).not_to have_key(:customer_waiting_since)
    end
  end

  # Revisão adversarial (item 5): sem as flags, a conversa só de cliente e pessoa não consulta os robôs da conta (como na
  # main, a consulta só acontece quando há mensagem de um AgentBot).
  it 'sem a flag, mensagem de cliente e de pessoa não consulta os robôs da conta' do
    falar(:incoming, contact, 2.minutes.ago)
    falar(:outgoing, admin, 1.minute.ago)
    tabelas = []
    contador = ->(*, payload) { tabelas << payload[:sql] if payload[:sql].include?('autonomia_agent_inboxes') }

    ActiveSupport::Notifications.subscribed(contador, 'sql.active_record') { contexto }

    expect(tabelas).to be_empty
  end

  it 'sem a flag, nada muda', :aggregate_failures do
    montar_conversa

    expect(contexto[:recent_messages]).to all(satisfy { |m| !m.key?(:after) })
    expect(contexto[:conversation_state]).not_to have_key(:customer_waiting_since)
  end
end
