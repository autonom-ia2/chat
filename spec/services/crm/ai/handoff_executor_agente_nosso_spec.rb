require 'rails_helper'

# #1673 (decisão do Rodrigo, 16/10): com um agente nosso no nome (o espelho da porta ou da área), o pedido de pessoa
# fica com a instrução dele (bot_handoff!); a IA do CRM não entrega a conversa por conta própria. O n8n, a conversa sem
# robô e a conta sem a Fase 2 seguem como antes. A troca por assunto (ResponsibleAgentSync) continua.
RSpec.describe Crm::Ai::HandoffExecutor do
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account) }
  let(:pedido) { { intent: 'transferir', reason: 'cliente pediu humano' } }

  before do
    inbox.add_members([pessoa.id])
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ pessoa.id => 'online' })
  end

  def card_com_regra(pipeline)
    card = create_card(pipeline: pipeline)
    card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    card.reload
  end

  def entregar(card, trigger: 'message')
    described_class.new(card: card, handoff: pedido, trigger: trigger).perform
  end

  describe 'com um agente nosso no nome' do
    it 'não entrega a conversa da porta e registra o motivo' do
      card = card_com_regra(comercial)
      allow(Rails.logger).to receive(:info).and_call_original

      result = entregar(card)

      expect(result).to have_attributes(status: :skipped, error: 'owned_by_our_agent')
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
      expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=skipped', 'motivo=owned_by_our_agent'))
    end

    it 'não entrega a conversa da área (o espelho dela conta como o agente)' do
      card = card_com_regra(comercial)
      conversation.update!(ai_assignee: espelho_area)

      expect(entregar(card).error).to eq('owned_by_our_agent')
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
    end

    # "Avaliar agora" (manual) e a fila antiga do card (drain) passam pelo executor: a regra é a mesma.
    it 'vale também para o "Avaliar agora" e para a fila' do
      card = card_com_regra(comercial)

      expect(entregar(card, trigger: 'manual').error).to eq('owned_by_our_agent')
      expect(entregar(card, trigger: 'drain').error).to eq('owned_by_our_agent')
      expect(conversation.reload.assignee_id).to be_nil
    end

    it 'com uma pessoa já no nome, o motivo continua sendo o de sempre' do
      card = card_com_regra(comercial)
      conversation.update!(assignee: pessoa)

      expect(entregar(card).error).to eq('already_assigned')
    end

    it 'a troca por assunto continua: o funil Suporte leva a conversa à área' do
      card = card_com_regra(suporte)

      expect(entregar(card).error).to eq('owned_by_our_agent')
      resultado = Crm::Ai::ResponsibleAgentSync.new(conversation: conversation.reload, motivo: Crm::Ai::ResponsibleAgentSync::FOCO).perform

      expect(resultado.trocou).to be(true)
      expect(conversation.reload).to have_attributes(ai_assignee: espelho_area, assignee_id: nil)
    end
  end

  it 'com o n8n (robô de fora) no nome, entrega pela regra, como hoje' do
    card = card_com_regra(comercial)
    n8n = AgentBot.create!(account: account, name: 'n8n', outgoing_url: 'https://n8n.invalid/webhook')
    conversation.update!(ai_assignee: n8n)

    result = entregar(card)

    expect(result).to have_attributes(status: :handed_off, assignee: pessoa)
    expect(conversation.reload.assignee_id).to eq(pessoa.id)
  end

  # O espelho que ficou no nome sem ninguém para responder por ele não segura a conversa: ela iria ficar sem ninguém.
  describe 'com o espelho de um agente que não responde agora' do
    it 'entrega quando o vínculo da porta foi arquivado' do
      card = card_com_regra(comercial)
      area_sumiu!(agente_da_porta)

      expect(entregar(card)).to have_attributes(status: :handed_off, assignee: pessoa)
    end

    it 'entrega quando o agente da porta está desligado' do
      card = card_com_regra(comercial)
      agente_da_porta.update_columns(enabled: false) # rubocop:disable Rails/SkipsModelValidations

      expect(entregar(card)).to have_attributes(status: :handed_off, assignee: pessoa)
    end

    it 'entrega quando os Agentes estão desligados na conta' do
      card = card_com_regra(comercial)
      allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(false)

      expect(entregar(card)).to have_attributes(status: :handed_off, assignee: pessoa)
    end
  end

  it 'sem robô no nome, entrega pela regra, como hoje' do
    card = card_com_regra(comercial)
    conversation.update!(ai_assignee: nil)

    expect(entregar(card)).to have_attributes(status: :handed_off, assignee: pessoa)
  end

  it 'sem a Fase 2 dos Agentes, nada muda: entrega mesmo com a porta no nome' do
    card = card_com_regra(comercial)
    Autonomia::Agents::Fase2.desligar!(account)

    expect(entregar(card)).to have_attributes(status: :handed_off, assignee: pessoa)
  end
end
