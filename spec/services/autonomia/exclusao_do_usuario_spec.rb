require 'rails_helper'

# #2135: excluir uma pessoa que tem card, lembrete, funil ou link de agendamento no CRM esbarrava nas chaves para users
# sem `on_delete` e o DELETE falhava. O primeiro exemplo lê as chaves do próprio Postgres, para tabela nova que apontar
# para users sem dizer o que fazer com a linha quebrar aqui, e não na exclusão de alguém em produção.
RSpec.describe Autonomia::ExclusaoDoUsuario do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:colega) { create(:user, account: account) }

  # Linhas cruas: o que importa é a chave apontar para a pessoa, não o fluxo de criar cada coisa.
  def linha(modelo, atributos)
    modelo.insert!(atributos, returning: :id).rows.first.first # rubocop:disable Rails/SkipsModelValidations
  end

  def funil
    @funil ||= linha(Crm::Pipeline, account_id: account.id, name: 'Vendas', created_by_id: user.id)
  end

  def etapa
    @etapa ||= linha(Crm::PipelineStage, account_id: account.id, pipeline_id: funil, name: 'Novo')
  end

  def card(dono)
    linha(Crm::Card, account_id: account.id, pipeline_id: funil, stage_id: etapa, title: 'Proposta', owner_id: dono.id)
  end

  def pagina
    @pagina ||= linha(Crm::AgentBookingProfile, account_id: account.id, slug: 'agenda')
  end

  def reuniao(autor, card_id)
    linha(Crm::Meeting, account_id: account.id, card_id: card_id, created_by_id: autor.id, title: 'Visita', provider: 0,
                        starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)
  end

  it 'diz o que fazer com toda chave para users que barraria o DELETE da pessoa' do
    chaves = ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT c.conrelid::regclass::text, a.attname
      FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
      WHERE c.contype = 'f' AND c.confrelid = 'users'::regclass AND c.confdeltype IN ('a', 'r')
    SQL
    tratadas = described_class.colunas_tratadas + described_class::SAEM_COM_O_USUARIO.keys.map { |tabela| [tabela, 'user_id'] }

    expect(chaves.uniq - tratadas).to eq([])
  end

  it 'apaga a pessoa e deixa o que é do negócio, sem o vínculo com ela' do
    do_user = card(user)
    do_colega = card(colega)
    conversa = create(:conversation, account: account)
    inbox = create(:inbox, account: account)
    ids = {
      vinculo: linha(Crm::CardConversation, account_id: account.id, card_id: do_colega, conversation_id: conversa.id, linked_by_id: user.id),
      lembrete: linha(Crm::FollowUp, account_id: account.id, title: 'Ligar', due_at: 1.day.from_now, card_id: do_colega,
                                     assignee_id: user.id, created_by_id: user.id),
      serie: linha(Crm::FollowUpSeries, account_id: account.id, title: 'Semanal', frequency: 1, starts_at: Time.current,
                                        card_id: do_colega, created_by_id: user.id),
      automacao: linha(Crm::StageAutomation, account_id: account.id, pipeline_id: funil, stage_id: etapa, name: 'Oi', created_by_id: user.id),
      caixa: linha(Crm::PipelineInbox, account_id: account.id, pipeline_id: funil, inbox_id: inbox.id, created_by_id: user.id),
      convidado: linha(Crm::MeetingGuest, account_id: account.id, meeting_id: reuniao(colega, do_colega), user_id: user.id,
                                          email: 'convidado@exemplo.invalid', guest_type: 2),
      modelo: linha(WhatsappApiMessageTemplate, account_id: account.id, name: 'oi', body: 'Olá', created_by_id: colega.id, updated_by_id: user.id),
      agente: linha(Autonomia::Agents::Agent, account_id: account.id, name: 'Atendente', created_by_id: user.id),
      visao_privada: linha(Crm::SavedView, account_id: account.id, user_id: user.id, name: 'Minhas', visibility: 0),
      visao_do_colega: linha(Crm::SavedView, account_id: account.id, user_id: colega.id, name: 'Dele', visibility: 0),
      link: linha(Crm::AgentBookingLink, account_id: account.id, booking_profile_id: pagina, agent_id: user.id, slug: 'agenda-pessoa')
    }
    ids[:conversa_do_agente] = linha(Autonomia::Agents::BuildThread, account_id: account.id, autonomia_agent_id: ids[:agente], created_by_id: user.id)

    user.destroy!

    depois = {
      usuario: User.exists?(user.id),
      cards: Crm::Card.unscoped.where(id: [do_user, do_colega]).order(:id).pluck(:owner_id),
      vinculo: Crm::CardConversation.unscoped.where(id: ids[:vinculo]).pick(:linked_by_id),
      lembrete: Crm::FollowUp.unscoped.where(id: ids[:lembrete]).pick(:assignee_id, :created_by_id),
      serie: Crm::FollowUpSeries.unscoped.where(id: ids[:serie]).pick(:created_by_id),
      automacao: Crm::StageAutomation.unscoped.where(id: ids[:automacao]).pick(:created_by_id),
      caixa: Crm::PipelineInbox.unscoped.where(id: ids[:caixa]).pick(:created_by_id),
      funil: Crm::Pipeline.unscoped.where(id: funil).pick(:created_by_id),
      convidado: Crm::MeetingGuest.unscoped.where(id: ids[:convidado]).pick(:user_id, :email),
      modelo: WhatsappApiMessageTemplate.unscoped.where(id: ids[:modelo]).pick(:created_by_id, :updated_by_id),
      agente: Autonomia::Agents::Agent.unscoped.where(id: ids[:agente]).pick(:created_by_id),
      conversa_do_agente: Autonomia::Agents::BuildThread.unscoped.where(id: ids[:conversa_do_agente]).pick(:created_by_id),
      visoes: Crm::SavedView.unscoped.where(id: [ids[:visao_privada], ids[:visao_do_colega]]).pluck(:id),
      link: Crm::AgentBookingLink.unscoped.exists?(ids[:link])
    }

    expect(depois).to eq(
      usuario: false, cards: [nil, colega.id], vinculo: nil, lembrete: [nil, nil], serie: nil, automacao: nil, caixa: nil, funil: nil,
      convidado: [nil, 'convidado@exemplo.invalid'], modelo: [colega.id, nil], agente: nil, conversa_do_agente: nil,
      visoes: [ids[:visao_do_colega]], link: false
    )
  end

  it 'refaz os contadores de quem vê o card depois do commit, por conta' do
    card(user)
    allow(Crm::Access::CountInvalidation).to receive(:card_changed!)

    user.destroy!

    expect(Crm::Access::CountInvalidation).to have_received(:card_changed!).with(account.id, []).once
  end

  it 'pelo DeleteObjectJob, que é o caminho de quem sai da última conta' do
    card(user)

    DeleteObjectJob.perform_now(user)

    expect(User.exists?(user.id)).to be(false)
  end

  describe 'linha que ainda espera decisão' do
    it 'não apaga nem altera nada e diz quais tabelas barraram' do
      do_user = card(user)
      reuniao(user, do_user)
      visao = linha(Crm::SavedView, account_id: account.id, user_id: user.id, name: 'Minhas', visibility: 0)
      allow(Rails.logger).to receive(:warn)

      expect(user.destroy).to be(false)

      expect(User.exists?(user.id)).to be(true)
      expect(Crm::Card.unscoped.find(do_user).owner_id).to eq(user.id)
      expect(Crm::SavedView.unscoped.exists?(visao)).to be(true)
      expect(user.errors.full_messages.join).to include('crm_meetings')
      expect(Rails.logger).to have_received(:warn).with("[ExclusaoDoUsuario] usuario=#{user.id} não saiu: crm_meetings esperam decisão (#2135)")
    end

    it 'barra campanha, modelo, visão compartilhada, lembrete e série avulsos de quem sai' do
      linha(WhatsappApiCampaign, account_id: account.id, title: 'Promo', created_by_id: user.id)
      linha(WhatsappApiMessageTemplate, account_id: account.id, name: 'oi', body: 'Olá', created_by_id: user.id)
      linha(Crm::SavedView, account_id: account.id, user_id: user.id, name: 'Do time', visibility: 1)
      linha(Crm::FollowUp, account_id: account.id, title: 'Reunião de equipe', due_at: 1.day.from_now, created_by_id: user.id)
      linha(Crm::FollowUpSeries, account_id: account.id, title: 'Semanal', frequency: 1, starts_at: Time.current, created_by_id: user.id)

      expect { user.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)

      expect(user.errors.full_messages.join).to include(
        'whatsapp_api_campaigns, whatsapp_api_message_templates, crm_saved_views, crm_follow_ups, crm_follow_up_series'
      )
    end

    it 'o DeleteObjectJob termina sem erro, para não repetir o que só a decisão destrava' do
      reuniao(user, card(colega))

      expect { DeleteObjectJob.perform_now(user) }.not_to raise_error
      expect(User.exists?(user.id)).to be(true)
    end
  end

  it 'manda a prévia do link de agendamento para o purge' do
    link = Crm::AgentBookingLink.find(linha(Crm::AgentBookingLink, account_id: account.id, booking_profile_id: pagina, agent_id: user.id,
                                                                   slug: 'agenda-pessoa'))
    link.preview_image.attach(io: StringIO.new('png'), filename: 'previa.png')

    user.destroy!

    expect(ActiveStorage::Attachment.where(record_type: 'Crm::AgentBookingLink', record_id: link.id)).to be_empty
  end
end
