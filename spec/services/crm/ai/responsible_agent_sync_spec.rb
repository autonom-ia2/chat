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

  def passagens
    Crm::Passagem.where(conversation_id: conversation.id).order(:id)
  end

  def eventos_durante(&)
    eventos = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { eventos << payload }, described_class::EVENTO_TROCA, &)
    eventos
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

    it 'troca pelo PassarParaIa: uma passagem da porta para a área, com motivo assunto, pedida pelo sistema' do
      card = create_card(pipeline: suporte)

      expect(sync).to have_attributes(trocou: true, codigo: :passou)

      expect(passagens.sole).to have_attributes(de_type: 'Autonomia::Agents::Agent', de_id: agente_da_porta.id,
                                                para_type: 'Autonomia::Agents::Agent', para_id: area.id, motivo: 'assunto',
                                                pedida_por_type: nil, card_id: card.id, devolvida_em: nil)
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

    it 'a troca que segue o pedido do agente fica como ABRIR na atividade, com o transfer_id no evento' do
      create_card(pipeline: comercial)
      eventos = []
      ActiveSupport::Notifications.subscribed(->(*, payload) { eventos << payload }, described_class::EVENTO_TROCA) do
        perform_enqueued_jobs do
          Crm::Subjects::Abrir.new(conversation: conversation, pipeline: suporte, resumo: 'Senha', motivo: 'suporte',
                                   origem: 'porta', transfer_id: 'tr-7').call
        end
      end

      expect(eventos.sole).to include(motivo: 'assunto', transfer_id: 'tr-7', to_bot: espelho_area, por: :crm)
      expect(trocas.sole.payload).to include('motivo' => 'abrir', 'transfer_id' => 'tr-7')
    end

    it 'não entrega à área com o CRM desligado na caixa' do
      create_card(pipeline: suporte)
      account.crm_inbox_settings.find_by(inbox: inbox).update!(crm_enabled: false)

      expect(sync.trocou).to be(false)
      expect(Crm::Ai::Config.destinos_para(conversation.reload)).to eq([])
    end

    it 'nem no pedido do agente (ABRIR) entrega a conversa resolvida: o PassarParaIa não reabre conversa' do
      create_card(pipeline: suporte)
      conversation.update!(status: :resolved)

      expect(sync(described_class::ABRIR).trocou).to be(false)
      expect(conversation.reload).to have_attributes(ai_assignee: porta, status: 'resolved')
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

    it 'um evento só, o do PassarParaIa, depois do commit' do
      create_card(pipeline: suporte)
      eventos = []
      callback = ->(*, payload) { eventos << payload }

      ActiveSupport::Notifications.subscribed(callback, described_class::EVENTO_TROCA) do
        ActiveRecord::Base.transaction do
          sync
          expect(eventos).to be_empty
        end
      end

      expect(eventos.sole).to eq(conversation: conversation, from_bot: porta, to_bot: espelho_area, agent: area,
                                 transfer_id: nil, motivo: 'assunto', origem: porta, por: :crm)
    end

    it 'recusa do PassarParaIa (pessoa_atribuida) não troca, não grava atividade nem passagem e não publica' do
      create_card(pipeline: suporte)
      recusa = Autonomia::Agents::PassarParaIa::Resultado.recusa(:pessoa_atribuida)
      allow(Autonomia::Agents::PassarParaIa).to receive(:call).and_return(recusa)
      resultado = nil

      eventos = eventos_durante { resultado = sync }

      expect(resultado).to have_attributes(trocou: false, codigo: :pessoa_atribuida)
      expect(Autonomia::Agents::PassarParaIa).to have_received(:call)
        .with(conversation: conversation, agent: area, por: :crm, motivo: 'assunto', origem: porta, transfer_id: nil)
      expect([eventos, trocas, passagens]).to all(be_empty)
      expect(conversation.reload.ai_assignee).to eq(porta)
    end
  end

  describe 'sem a Fase 2 dos Agentes' do
    before { Autonomia::Agents::Fase2.desligar!(account) }

    it 'não entrega a conversa à área' do
      create_card(pipeline: suporte)

      expect(sync.trocou).to be(false)
      expect(conversation.reload.ai_assignee).to eq(porta)
    end

    it 'nem devolve à porta e nem chama o PassarParaIa (sem área, quem responde é sempre a porta)' do
      card = create_card(pipeline: suporte)
      conversation.update!(ai_assignee: espelho_area)
      card.update!(pipeline: comercial, stage: comercial.stages.first)
      allow(Autonomia::Agents::PassarParaIa).to receive(:call).and_call_original

      expect(sync(described_class::PIPELINE, card_id: card.id).trocou).to be(false)
      expect(Autonomia::Agents::PassarParaIa).not_to have_received(:call)
      expect(conversation.reload.ai_assignee).to eq(espelho_area)
      expect(passagens).to be_empty
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

    it 'com a marca do motor de entrega (segurando para uma pessoa): a marca fica' do
      Crm::Entrega::Marca.marcar(conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: 'robo_pediu', falha: 'ninguem_cuida')
      conversation.save!

      expect(sync.trocou).to be(false)
      expect(conversation.reload).to have_attributes(ai_assignee: porta, crm_delivery_pending?: true)
      expect(passagens).to be_empty
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

    it 'quando o responsável não é mais área da caixa (sem espelho não há como postar)' do
      area_sumiu!

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

    # A ida de verdade: a porta passa para a área pelo assunto (passagem 1, em aberto).
    before { raise 'a ida não trocou' unless sync.trocou }

    def volta_gravada!
      ida, volta = passagens.to_a
      expect(ida).to have_attributes(para_id: area.id, devolvida_em: be_present, devolvida_por_id: area.id)
      expect(volta).to have_attributes(de_id: area.id, para_type: 'Autonomia::Agents::Agent', para_id: agente_da_porta.id,
                                       motivo: 'assunto', devolvida_em: nil)
    end

    it 'quando o card em atendimento passa para um funil sem responsável' do
      card.update!(pipeline: comercial, stage: comercial.stages.first)

      resultado = sync(described_class::PIPELINE, card_id: card.id)

      expect(resultado).to have_attributes(trocou: true, para_agent_bot_id: porta.id, autonomia_agent_id: agente_da_porta.id)
      expect(conversation.reload.ai_assignee).to eq(porta)
      volta_gravada!
    end

    it 'quando o card em atendimento passa para um funil cujo responsável não é mais área da caixa' do
      outra_area = criar_agente('Área Comercial')
      Autonomia::Agents::Areas.vincular!(agent: outra_area, inbox: inbox)
      Crm::InboxAiAgent.create!(account: account, inbox: inbox, pipeline: comercial, agent: outra_area)
      area_sumiu!(outra_area)
      card.update!(pipeline: comercial, stage: comercial.stages.first)

      resultado = sync(described_class::PIPELINE, card_id: card.id)

      expect(resultado).to have_attributes(trocou: true, para_agent_bot_id: porta.id, autonomia_agent_id: agente_da_porta.id)
      expect(conversation.reload.ai_assignee).to eq(porta)
    end

    it 'quando o foco passa para outro card, de funil sem responsável: um evento e a devolução gravada' do
      create_card(pipeline: comercial)
      resultado = nil

      eventos = eventos_durante { resultado = sync(described_class::FOCO) }

      expect(resultado).to have_attributes(trocou: true, para_agent_bot_id: porta.id)
      expect(conversation.reload.ai_assignee).to eq(porta)
      expect(eventos.sole).to include(from_bot: espelho_area, to_bot: porta, agent: agente_da_porta, motivo: 'assunto')
      volta_gravada!
    end

    it 'o pedido do agente (ABRIR) não devolve à porta sozinho' do
      create_card(pipeline: comercial)

      expect(sync(described_class::ABRIR).trocou).to be(false)
      expect(conversation.reload.ai_assignee).to eq(espelho_area)
    end

    it 'a área que saiu da caixa (vínculo removido) com a conversa: volta à porta' do
      area_sumiu!
      create_card(pipeline: comercial)

      expect(sync(described_class::FOCO)).to have_attributes(trocou: true, para_agent_bot_id: porta.id)
      expect(conversation.reload.ai_assignee).to eq(porta)
      expect(passagens.last).to have_attributes(de_id: area.id, para_id: agente_da_porta.id, motivo: 'assunto')
    end

    it 'robô externo com a conversa não é tirado pela volta à porta' do
      externo = create(:agent_bot, account: account, name: 'n8n')
      conversation.update!(ai_assignee: externo)
      create_card(pipeline: comercial)

      expect(sync(described_class::FOCO).trocou).to be(false)
      expect(conversation.reload.ai_assignee).to eq(externo)
    end

    it 'porta que não é agente nosso (robô externo): nada a pedir' do
      create_card(pipeline: comercial)
      allow(Autonomia::Agents::QuemResponde).to receive(:porta_da_caixa).and_return(nil)

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
