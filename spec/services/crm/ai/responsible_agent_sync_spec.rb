require 'rails_helper'

RSpec.describe Crm::Ai::ResponsibleAgentSync do
  include ActiveJob::TestHelper
  include_context 'with crm responsible agent'

  def sync(motivo = described_class::FOCO, card_id: nil)
    described_class.new(conversation: conversation.reload, motivo: motivo, card_id: card_id).perform
  end

  def trocas
    Crm::Activity.where(conversation_id: conversation.id, event_type: described_class::EVENTO)
  end

  describe 'troca para o responsável' do
    it 'entrega a conversa ao espelho do agente do funil em atendimento e grava a troca' do
      card = create_card(pipeline: suporte)

      resultado = sync

      expect(resultado).to have_attributes(trocou: true, de_agent_bot_id: porta.id, para_agent_bot_id: espelho_area.id,
                                           autonomia_agent_id: area.id)
      expect(conversation.reload).to have_attributes(ai_assignee: espelho_area, assignee_id: nil, status: 'open')
      expect(trocas.sole).to have_attributes(card_id: card.id)
      expect(trocas.sole.payload).to include('motivo' => 'foco', 'para_agent_bot_id' => espelho_area.id)
    end

    it 'grava o transfer_id do pedido do agente (Abrir) e não o reaproveita numa troca seguinte' do
      create_card(pipeline: comercial)
      Crm::Subjects::Abrir.new(conversation: conversation, pipeline: suporte, resumo: 'Senha', motivo: 'suporte',
                               origem: 'porta', transfer_id: 'tr-42').call

      expect(sync(described_class::ABRIR).transfer_id).to eq('tr-42')
      expect(trocas.sole.payload['transfer_id']).to eq('tr-42')

      conversation.update!(ai_assignee: porta)
      expect(sync.transfer_id).to be_nil
    end

    it 'no pedido do agente (ABRIR) entrega mesmo a conversa resolvida: o agente está atendendo agora' do
      create_card(pipeline: suporte)
      conversation.update!(status: :resolved)

      expect(sync(described_class::ABRIR).trocou).to be(true)
      expect(conversation.reload).to have_attributes(ai_assignee: espelho_area, status: 'open')
    end

    it 'não usa o transfer_id de um pedido antigo que não virou troca' do
      create_card(pipeline: comercial)
      resultado = Crm::Subjects::Abrir.new(conversation: conversation, pipeline: suporte, resumo: 'Senha', motivo: 'suporte',
                                           origem: 'porta', transfer_id: 'tr-velho').call
      expect(resultado.ok).to be(true)

      travel_to(described_class::JANELA_DO_PEDIDO.from_now + 1.minute) do
        expect(sync).to have_attributes(trocou: true, transfer_id: nil)
      end
    end

    it 'publica o evento da troca depois do commit, para o Agentes IA enfileirar a resposta do destino' do
      create_card(pipeline: suporte)
      eventos = []
      callback = ->(*, payload) { eventos << payload }

      ActiveSupport::Notifications.subscribed(callback, described_class::EVENTO_TROCA) do
        ActiveRecord::Base.transaction do
          sync
          expect(eventos).to be_empty
        end
      end

      expect(eventos.sole).to include(conversation_id: conversation.id, para_agent_bot_id: espelho_area.id, trocou: true)
    end
  end

  describe 'não troca' do
    before { create_card(pipeline: suporte) }

    it 'e não publica o evento quando nada muda' do
      conversation.update!(assignee: admin)
      eventos = []

      ActiveSupport::Notifications.subscribed(->(*) { eventos << 1 }, described_class::EVENTO_TROCA) { sync }

      expect(eventos).to be_empty
    end

    it 'para o responsável de funil arquivado ou com a IA do funil desligada' do
      suporte.update!(metadata: suporte.metadata.merge('ai' => suporte.metadata['ai'].merge('enabled' => false)))
      expect(sync.trocou).to be(false)

      suporte.update!(metadata: suporte.metadata.merge('ai' => suporte.metadata['ai'].merge('enabled' => true)), status: :archived)
      expect(sync.trocou).to be(false)
      expect(conversation.reload.ai_assignee).to eq(porta)
    end

    it 'com uma pessoa atribuída' do
      conversation.update!(assignee: admin)

      expect(sync.trocou).to be(false)
      expect(conversation.reload.assignee).to eq(admin)
      expect(trocas).to be_empty
    end

    it 'com a conversa esperando uma pessoa' do
      conversation.update!(ai_assignee: porta)
      esperar_pessoa!

      expect(sync.trocou).to be(false)
      expect(conversation.reload.ai_assignee).to eq(porta)
    end

    it 'sem robô atendendo (a conversa está na fila de pessoas)' do
      conversation.update!(ai_assignee: nil)

      expect(sync.trocou).to be(false)
      expect(conversation.reload.ai_assignee).to be_nil
    end

    it 'com a conversa resolvida' do
      conversation.update!(status: :resolved)

      expect(sync.trocou).to be(false)
      expect(conversation.reload).to have_attributes(status: 'resolved', ai_assignee: porta)
    end

    it 'quando o responsável não tem vínculo com a caixa (sem espelho não há como postar)' do
      Autonomia::Agents::AgentInbox.where(agent: area).update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(sync.trocou).to be(false)
      expect(conversation.reload.ai_assignee).to eq(porta)
    end

    it 'quando o responsável já atende' do
      conversation.update!(ai_assignee: espelho_area)

      expect(sync.trocou).to be(false)
      expect(trocas).to be_empty
    end
  end

  describe 'volta para a porta' do
    let!(:card) { create_card(pipeline: suporte) }

    before { conversation.update!(ai_assignee: espelho_area) }

    it 'quando o card em atendimento passa para um funil sem responsável' do
      card.update!(pipeline: comercial, stage: comercial.stages.first)

      resultado = sync(described_class::PIPELINE, card_id: card.id)

      expect(resultado).to have_attributes(trocou: true, para_agent_bot_id: porta.id, autonomia_agent_id: nil)
      expect(conversation.reload.ai_assignee).to eq(porta)
    end

    it 'não volta sozinha na troca de foco para um funil sem responsável' do
      create_card(pipeline: comercial)

      expect(sync(described_class::FOCO).trocou).to be(false)
      expect(conversation.reload.ai_assignee).to eq(espelho_area)
    end

    it 'não volta quando o card que mudou de funil não é o assunto em atendimento' do
      outro = create_card(pipeline: suporte, focused_at: 1.day.ago)
      outro.update!(pipeline: comercial, stage: comercial.stages.first)

      expect(sync(described_class::PIPELINE, card_id: outro.id).trocou).to be(false)
      expect(conversation.reload.ai_assignee).to eq(espelho_area)
    end
  end

  describe 'disparo depois do commit' do
    it 'a troca de foco enfileira o sync da conversa' do
      create_card(pipeline: comercial)
      card = create_card(pipeline: suporte, focused_at: nil)
      clear_enqueued_jobs

      Crm::Cards::Focus.new(account: account, card: card, conversation: conversation).perform

      expect(Crm::Ai::ResponsibleAgentSyncJob).to have_been_enqueued.with(conversation.id, 'foco', nil)
    end

    it 'o card que muda de funil enfileira o sync de cada conversa aberta dele' do
      card = create_card(pipeline: suporte)
      clear_enqueued_jobs

      Crm::Cards::Mover.new(card: card, actor: admin, target_stage: comercial.stages.first,
                            automation_context: { skip_automations: true }).perform

      expect(Crm::Ai::ResponsibleAgentSyncJob).to have_been_enqueued.with(conversation.id, 'pipeline', card.id)
    end

    it 'nada enfileira com a mudança ainda dentro da transação, nem em conta sem responsável configurado' do
      card = create_card(pipeline: suporte)
      clear_enqueued_jobs

      ActiveRecord::Base.transaction do
        card.update!(pipeline: comercial, stage: comercial.stages.first)
        expect(Crm::Ai::ResponsibleAgentSyncJob).not_to have_been_enqueued
      end
      expect(Crm::Ai::ResponsibleAgentSyncJob).to have_been_enqueued.once

      clear_enqueued_jobs
      Crm::InboxAiAgent.delete_all
      card.update!(pipeline: suporte, stage: suporte.stages.first)
      expect(Crm::Ai::ResponsibleAgentSyncJob).not_to have_been_enqueued
    end
  end
end
