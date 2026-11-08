require 'rails_helper'

# Contrato com Agentes IA (#1433/#1447): o agente abre um assunto num funil e a conversa vai para o responsável.
RSpec.describe Crm::Subjects::Abrir do
  include ActiveJob::TestHelper
  include_context 'with crm responsible agent'

  def abrir(pipeline = suporte, **extra)
    described_class.new(conversation: conversation, pipeline: pipeline, resumo: 'Troca de senha do portal',
                        motivo: 'Cliente pediu suporte', origem: 'porta', pedido_por: 'cliente', transfer_id: 'tr-1', **extra).call
  end

  def pedidos
    Crm::Activity.where(conversation_id: conversation.id, event_type: described_class::EVENTO)
  end

  describe 'recusas: nada é gravado' do
    before { create_card(pipeline: comercial) }

    def expect_recusa(recusa)
      resultado = nil
      expect { resultado = abrir }.not_to(change { account.crm_cards.count })

      expect(resultado).to have_attributes(ok: false, recusa: recusa, acao: nil, card: nil)
      expect(pedidos).to be_empty
      expect(Crm::Ai::ResponsibleAgentSyncJob).not_to have_been_enqueued.with(conversation.id, 'abrir', nil)
    end

    it 'cada recusa tem nome em en e pt_BR' do
      described_class::RECUSAS.each do |recusa|
        chave = described_class::Resultado.new(recusa: recusa).recusa_i18n_key
        expect([I18n.exists?(chave, :en), I18n.exists?(chave, :pt_BR)]).to eq([true, true]), chave
      end
    end

    it ':sem_crm com o CRM desligado na caixa' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(crm_enabled: false)
      expect_recusa(:sem_crm)
    end

    # #2084: o contato foi marcado parceiro do mercado ou não é negócio.
    it ':fora_do_funil com o contato marcado e a flag contato_relacao ligada' do
      account.enable_features!('contato_relacao')
      conversation.contact.update!(relacao: :parceiro)
      expect_recusa(:fora_do_funil)
    end

    it 'com a flag contato_relacao desligada, a marca não recusa' do
      conversation.contact.update!(relacao: :nao_e_negocio)
      expect(abrir).to have_attributes(ok: true)
    end

    it ':funil_invalido para funil arquivado ou fora da caixa' do
      suporte.update!(status: :archived)
      expect_recusa(:funil_invalido)

      suporte.update!(status: :active)
      suporte.pipeline_inboxes.destroy_all
      expect_recusa(:funil_invalido)
    end

    it ':funil_invalido para funil de outra conta' do
      outra = create(:account)
      funil = create_crm_pipeline(account: outra, user: create(:user, account: outra, role: :administrator)).first

      expect(abrir(funil)).to have_attributes(ok: false, recusa: :funil_invalido)
    end

    it ':sem_agente_responsavel quando ninguém cuida do funil na caixa' do
      Crm::InboxAiAgent.delete_all
      expect_recusa(:sem_agente_responsavel)
    end

    it ':agente_fora_da_caixa quando o responsável não é mais área da caixa' do
      area_sumiu!
      expect_recusa(:agente_fora_da_caixa)
    end

    it ':sem_agente_responsavel quando a área sai pela tela e o agente para (era a última caixa dele)' do
      Autonomia::Agents::Areas.desvincular!(agent: area, inbox: inbox)

      expect(area.reload).to have_attributes(status: 'paused', enabled: false)
      expect_recusa(:sem_agente_responsavel)
    end

    it ':sem_agente_responsavel sem a Fase 2 dos Agentes: quem responde é a porta' do
      Autonomia::Agents::Fase2.desligar!(account)
      expect_recusa(:sem_agente_responsavel)
    end

    it ':pessoa_atribuida quando uma pessoa atende' do
      conversation.update!(assignee: admin)
      expect_recusa(:pessoa_atribuida)
    end

    it ':esperando_pessoa quando a conversa espera uma pessoa' do
      esperar_pessoa!
      expect_recusa(:esperando_pessoa)
    end

    it ':esperando_pessoa quando nenhum robô atende (a conversa está na fila de pessoas)' do
      conversation.update!(ai_assignee: nil)
      expect_recusa(:esperando_pessoa)
    end
  end

  it ':aberto cria o card na 1ª etapa, vira o assunto atual e guarda o pedido' do
    atual = create_card(pipeline: comercial)
    create_crm_stage(account: account, pipeline: suporte, name: 'Em andamento', position: 1)

    resultado = abrir

    expect(resultado).to have_attributes(ok: true, acao: :aberto, pipeline: suporte, agente: area, recusa: nil)
    card = resultado.card
    expect(card).to have_attributes(pipeline_id: suporte.id, title: 'Troca de senha do portal',
                                    stage_id: suporte.stages.order(:position).first.id)
    expect(card.metadata.dig('subject', 'source')).to eq('agente')
    expect(Crm::Cards::ConversationCardFinder.new(account: account).find(conversation)).to eq(card)
    expect(atual.reload).to be_open
    expect(pedidos.sole.payload).to include('acao' => 'aberto', 'resumo' => 'Troca de senha do portal', 'motivo' => 'Cliente pediu suporte',
                                            'origem' => 'porta', 'pedido_por' => 'cliente', 'transfer_id' => 'tr-1',
                                            'autonomia_agent_id' => area.id)
    expect(Crm::Ai::ResponsibleAgentSyncJob).to have_been_enqueued.with(conversation.id, 'abrir', nil)
  end

  describe 'respeita o assunto que uma pessoa escolheu há pouco (#1260)' do
    def escolhido_por_pessoa(card, quando: 1.hour.ago)
      card.card_conversations.find_by(conversation: conversation).update!(focused_at: quando, focused_by_id: admin.id)
      card
    end

    it 'recusa abrir card novo com :assunto_escolhido_por_pessoa, sem gravar nada' do
      escolhido_por_pessoa(create_card(pipeline: comercial))

      expect { expect(abrir).to have_attributes(ok: false, recusa: :assunto_escolhido_por_pessoa, agente: area) }
        .not_to(change { account.crm_cards.count })
      expect(pedidos).to be_empty
      expect(Crm::Ai::ResponsibleAgentSyncJob).not_to have_been_enqueued.with(conversation.id, 'abrir', nil)
    end

    it 'recusa voltar a outro card aberto e não mexe no foco' do
      existente = create_card(pipeline: suporte, focused_at: 2.days.ago)
      atual = escolhido_por_pessoa(create_card(pipeline: comercial))

      expect(abrir).to have_attributes(ok: false, recusa: :assunto_escolhido_por_pessoa)
      expect(Crm::Cards::ConversationCardFinder.new(account: account).find(conversation)).to eq(atual)
      expect(existente.card_conversations.first.reload.focused_at).to be < 1.day.ago
    end

    it 'segue valendo :ja_no_funil, que não troca o assunto' do
      escolhido_por_pessoa(create_card(pipeline: suporte))

      expect(abrir).to have_attributes(ok: true, acao: :ja_no_funil)
    end

    it 'depois do tempo de respeito, abre normalmente' do
      escolhido_por_pessoa(create_card(pipeline: comercial), quando: Crm::Subjects::RESPEITO_AO_FOCO.ago - 1.minute)

      resultado = abrir

      expect(resultado).to have_attributes(ok: true, acao: :aberto)
      expect(Crm::Cards::ConversationCardFinder.new(account: account).find(conversation)).to eq(resultado.card)
    end
  end

  it ':reaproveitado volta ao card aberto do funil, sem criar outro' do
    existente = create_card(pipeline: suporte, focused_at: 2.hours.ago)
    create_card(pipeline: comercial)

    resultado = abrir

    expect(resultado).to have_attributes(ok: true, acao: :reaproveitado, card: existente)
    expect(account.crm_cards.where(pipeline: suporte).count).to eq(1)
    expect(Crm::Cards::ConversationCardFinder.new(account: account).find(conversation)).to eq(existente)
    expect(pedidos.sole).to have_attributes(card_id: existente.id)
  end

  it ':ja_no_funil quando o assunto em atendimento já é do funil' do
    atual = create_card(pipeline: suporte)

    resultado = abrir

    expect(resultado).to have_attributes(ok: true, acao: :ja_no_funil, card: atual, agente: area)
    expect(account.crm_cards.count).to eq(1)
    expect(pedidos.sole.payload['acao']).to eq('ja_no_funil')
    expect(Crm::Ai::ResponsibleAgentSyncJob).to have_been_enqueued.with(conversation.id, 'abrir', nil)
  end

  it 'enfileira o sync só depois do commit de quem chamou' do
    create_card(pipeline: comercial)
    clear_enqueued_jobs

    ActiveRecord::Base.transaction do
      abrir
      expect(Crm::Ai::ResponsibleAgentSyncJob).not_to have_been_enqueued.with(conversation.id, 'abrir', nil)
    end

    expect(Crm::Ai::ResponsibleAgentSyncJob).to have_been_enqueued.with(conversation.id, 'abrir', nil)
  end
end
