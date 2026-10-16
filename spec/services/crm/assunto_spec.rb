require 'rails_helper'

# #1606 (corrida h): uma regra só de "qual funil manda", usada pela Entrega, pelo Sync, pelo Evaluator, pelo Canceler
# do follow-up e pelo leitor robo_do_funil do Agentes IA.
RSpec.describe Crm::Assunto do
  include_context 'with crm responsible agent'

  describe '.funil_atual' do
    it 'é o card aberto do assunto em foco, relido na hora' do
      comercial_card = create_card(pipeline: comercial, focused_at: 2.minutes.ago)
      expect(described_class.funil_atual(conversation)).to eq(comercial_card)

      suporte_card = create_card(pipeline: suporte)
      expect(described_class.funil_atual(conversation)).to eq(suporte_card)
      expect(described_class.atual?(comercial_card, conversation)).to be(false)
      expect(described_class.atual?(suporte_card, conversation)).to be(true)
    end

    it 'card fechado não manda; sem card, nil' do
      expect(described_class.funil_atual(conversation)).to be_nil

      create_card(pipeline: suporte).update!(status: :won)
      expect(described_class.funil_atual(conversation)).to be_nil
      expect(described_class.funil_atual(nil)).to be_nil
    end
  end

  describe 'Crm::Ai::Config.robo_do_funil (contrato com o Agentes IA)' do
    it 'é o espelho de área do responsável do funil em foco' do
      create_card(pipeline: suporte)

      expect(Crm::Ai::Config.robo_do_funil(conversation)).to eq(espelho_area)
    end

    it 'é nil sem card, em funil sem responsável, com o agente parado, sem vínculo de área ou sem a Fase 2', :aggregate_failures do
      expect(Crm::Ai::Config.robo_do_funil(conversation)).to be_nil

      card = create_card(pipeline: comercial)
      expect(Crm::Ai::Config.robo_do_funil(conversation)).to be_nil

      card.update!(pipeline: suporte, stage: suporte.stages.first)
      area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations
      expect(Crm::Ai::Config.robo_do_funil(conversation)).to be_nil

      area.update_columns(status: Autonomia::Agents::Agent.statuses[:active]) # rubocop:disable Rails/SkipsModelValidations
      area_sumiu!
      expect(Crm::Ai::Config.robo_do_funil(conversation)).to be_nil
    end

    it 'é nil com a IA do funil desligada' do
      create_card(pipeline: suporte)
      suporte.update!(metadata: { 'ai' => { 'enabled' => false } })

      expect(Crm::Ai::Config.robo_do_funil(conversation)).to be_nil
    end

    it 'é nil sem a Fase 2 dos Agentes' do
      create_card(pipeline: suporte)
      Autonomia::Agents::Fase2.desligar!(account)

      expect(Crm::Ai::Config.robo_do_funil(conversation.reload)).to be_nil
    end
  end

  describe 'Canceler do follow-up (corrida f)' do
    def cadencia_ativa(card)
      card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => true } } })
      account.crm_follow_ups.create!(card: card, conversation: conversation, title: 'Toque', due_at: 1.hour.from_now,
                                     timezone: 'UTC', automation_mode: :reminder_only, metadata: { 'source' => 'ai_followup' })
    end

    def mensagem_do_cliente
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'Oi')
    end

    it 'a resposta sobre outro assunto não para a cadência do card que não está em foco' do
      antigo = create_card(pipeline: comercial, focused_at: 2.minutes.ago)
      toque = cadencia_ativa(antigo)
      create_card(pipeline: suporte)

      Crm::FollowUps::AutoFollowupCanceler.new(card: antigo, message: mensagem_do_cliente).maybe_cancel

      expect(toque.reload.status).to eq('pending')
    end

    it 'a resposta no assunto em foco para a cadência, como antes' do
      card = create_card(pipeline: suporte)
      toque = cadencia_ativa(card)

      Crm::FollowUps::AutoFollowupCanceler.new(card: card, message: mensagem_do_cliente).maybe_cancel

      expect(toque.reload.status).to eq('canceled')
    end
  end

  describe 'a passagem da IA do CRM reconfere o assunto (corrida c)' do
    it 'não passa pelo card que deixou de ser o assunto durante a avaliação' do
      antigo = create_card(pipeline: comercial, focused_at: 2.minutes.ago)
      antigo.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
      create_card(pipeline: suporte)
      allow(Crm::Entrega).to receive(:new)

      resultado = Crm::Ai::HandoffExecutor.new(card: antigo.reload, handoff: { intent: 'transferir' }).perform

      expect(resultado).to have_attributes(status: :skipped, error: 'assunto_mudou')
      expect(Crm::Entrega).not_to have_received(:new)
    end

    # Sem robô no nome: com a porta (agente nosso) dona da conversa, a IA do CRM não entrega por conta própria (#1673).
    it 'passa quando o card ainda é o assunto' do
      conversation.update!(ai_assignee: nil)
      card = create_card(pipeline: suporte)
      card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
      entrega = instance_double(Crm::Entrega, call: Crm::Entrega::Resultado.new(status: :segurando, motivo: 'ninguem_online'))
      allow(Crm::Entrega).to receive(:new).and_return(entrega)

      Crm::Ai::HandoffExecutor.new(card: card.reload, handoff: { intent: 'transferir' }).perform

      expect(entrega).to have_received(:call)
    end
  end
end
