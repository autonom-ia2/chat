require 'rails_helper'

# #2135: excluir uma pessoa que tem card, lembrete, reunião, campanha ou link de agendamento no CRM esbarrava nas chaves
# para users sem `on_delete` e o DELETE falhava. Os dois primeiros exemplos leem as chaves do próprio Postgres, para
# tabela nova que apontar para users sem dizer o que fazer com a linha quebrar aqui, e não na exclusão de alguém em
# produção.
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

  def reuniao(autor, card_id, quando: 1.day.from_now)
    linha(Crm::Meeting, account_id: account.id, card_id: card_id, created_by_id: autor.id, title: 'Visita', provider: 2,
                        status: 1, starts_at: quando, ends_at: quando + 1.hour)
  end

  # [tabela, coluna, ação] das chaves para users. Ação: 'a' NO ACTION, 'r' RESTRICT, 'c' CASCADE, 'n' SET NULL.
  def chaves_para_users
    ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT c.conrelid::regclass::text, a.attname, c.confdeltype, a.attnotnull
      FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
      WHERE c.contype = 'f' AND c.confrelid = 'users'::regclass
    SQL
  end

  it 'diz o que fazer com toda chave para users que barraria o DELETE da pessoa' do
    barram = chaves_para_users.filter_map { |tabela, coluna, acao, _| [tabela, coluna] if %w[a r].include?(acao) }
    tratadas = described_class.colunas_tratadas + described_class::SAEM_COM_O_USUARIO.keys.map { |tabela| [tabela, 'user_id'] }

    expect(barram.uniq - tratadas).to eq([])
  end

  it 'só anula coluna que aceita nulo, pelo serviço ou pela chave' do
    anuladas = described_class::ANULAR.map { |modelo, coluna| [modelo.constantize.table_name, coluna.to_s] } +
               chaves_para_users.filter_map { |tabela, coluna, acao, _| [tabela, coluna] if acao == 'n' }
    obrigatorias = chaves_para_users.filter_map { |tabela, coluna, _, not_null| [tabela, coluna] if not_null }

    expect(anuladas & obrigatorias).to eq([])
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
      reuniao_passada: reuniao(user, do_colega, quando: 1.day.ago),
      campanha: linha(WhatsappApiCampaign, account_id: account.id, title: 'Promo', created_by_id: user.id),
      modelo: linha(WhatsappApiMessageTemplate, account_id: account.id, name: 'oi', body: 'Olá', created_by_id: user.id, updated_by_id: user.id),
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
      reuniao_passada: Crm::Meeting.unscoped.where(id: ids[:reuniao_passada]).pick(:created_by_id),
      campanha: WhatsappApiCampaign.unscoped.where(id: ids[:campanha]).pick(:created_by_id),
      modelo: WhatsappApiMessageTemplate.unscoped.where(id: ids[:modelo]).pick(:created_by_id, :updated_by_id),
      agente: Autonomia::Agents::Agent.unscoped.where(id: ids[:agente]).pick(:created_by_id),
      conversa_do_agente: Autonomia::Agents::BuildThread.unscoped.where(id: ids[:conversa_do_agente]).pick(:created_by_id),
      visoes: Crm::SavedView.unscoped.where(id: [ids[:visao_privada], ids[:visao_do_colega]]).pluck(:id),
      link: Crm::AgentBookingLink.unscoped.exists?(ids[:link])
    }

    expect(depois).to eq(
      usuario: false, cards: [nil, colega.id], vinculo: nil, lembrete: [nil, nil], serie: nil, automacao: nil, caixa: nil, funil: nil,
      convidado: [nil, 'convidado@exemplo.invalid'], reuniao_passada: nil, campanha: nil, modelo: [nil, nil], agente: nil,
      conversa_do_agente: nil, visoes: [ids[:visao_do_colega]], link: false
    )
  end

  it 'a reunião, a campanha e o modelo sem autor continuam editáveis, e criar ainda exige autor' do
    passada = Crm::Meeting.find(reuniao(user, card(colega), quando: 1.day.ago))

    user.destroy!

    expect(passada.reload.tap(&:validate).errors[:created_by]).to be_empty
    expect([Crm::Meeting, WhatsappApiCampaign, WhatsappApiMessageTemplate].map { |modelo| modelo.new.tap(&:validate).errors[:created_by] })
      .to all(be_present)
  end

  it 'apaga o lembrete e a série que só avisavam a pessoa, mesmo com administrador na conta' do
    create(:user, account: account, role: :administrator)
    lembrete = linha(Crm::FollowUp, account_id: account.id, title: 'Reunião de equipe', due_at: 1.day.from_now, created_by_id: user.id,
                                    assignee_id: user.id)
    serie = linha(Crm::FollowUpSeries, account_id: account.id, title: 'Semanal', frequency: 1, starts_at: Time.current, created_by_id: user.id)
    so_ela = linha(Crm::FollowUpSeries, account_id: account.id, title: 'Diária', frequency: 0, starts_at: Time.current, created_by_id: user.id,
                                        recipient_mode: 3, recipient_user_ids: [user.id])

    user.destroy!

    expect([Crm::FollowUp.unscoped.exists?(lembrete), Crm::FollowUpSeries.unscoped.exists?(id: [serie, so_ela])]).to eq([false, false])
  end

  describe 'o que passa para o primeiro administrador da conta' do
    let!(:administrador) { create(:user, account: account, role: :administrator) }

    # Lembrete do agente da reunião, como o agendamento cria: pendente, com quem atende.
    def lembrete_da(reuniao_id, card_id)
      lembrete = linha(Crm::FollowUp, account_id: account.id, title: 'Reunião', due_at: 1.day.from_now, card_id: card_id, assignee_id: user.id)
      Crm::Meeting.where(id: reuniao_id).update_all(reminder_id: lembrete) # rubocop:disable Rails/SkipsModelValidations
      lembrete
    end

    it 'passa a reunião futura e o lembrete dela, com a atividade no card, e deixa a passada sem autor' do
      do_colega = card(colega)
      futura = reuniao(user, do_colega)
      linha(Crm::MeetingGuest, account_id: account.id, meeting_id: futura, email: 'cliente@exemplo.invalid', guest_type: 1)
      lembrete = lembrete_da(futura, do_colega)
      passada = reuniao(user, do_colega, quando: 1.day.ago)

      user.destroy!

      expect(Crm::Meeting.where(id: [futura, passada]).order(:starts_at).pluck(:created_by_id)).to eq([nil, administrador.id])
      expect(Crm::FollowUp.find(lembrete).assignee_id).to eq(administrador.id)
      expect(Crm::Activity.where(card_id: do_colega, event_type: Crm::BookingV2::MeetingHandover::EVENT_TYPE).pick(:payload))
        .to include('meeting_id' => futura, 'from_user_id' => user.id, 'to_user_id' => administrador.id, 'reason' => 'user_deleted')
    end

    it 'passa a reunião futura com dado antigo que não valida mais, e o lembrete dela, sem a atividade' do
      do_colega = card(colega)
      futura = reuniao(user, do_colega)
      lembrete = lembrete_da(futura, do_colega)
      allow(Rails.logger).to receive(:warn)

      user.destroy!

      expect([Crm::Meeting.find(futura).created_by_id, Crm::FollowUp.find(lembrete).assignee_id]).to eq([administrador.id, administrador.id])
      expect(Rails.logger).to have_received(:warn).with("[ExclusaoDoUsuario] usuario=#{user.id} reunião #{futura} passada sem validação")
    end

    it 'passa a visão compartilhada' do
      visao = linha(Crm::SavedView, account_id: account.id, user_id: user.id, name: 'Do time', visibility: 1)

      user.destroy!

      expect(Crm::SavedView.find(visao).user_id).to eq(administrador.id)
    end

    it 'passa o lembrete e a série avulsos que avisam outra pessoa' do
      lembrete = linha(Crm::FollowUp, account_id: account.id, title: 'Ligar para o fornecedor', due_at: 1.day.from_now,
                                      created_by_id: user.id, assignee_id: colega.id)
      serie = linha(Crm::FollowUpSeries, account_id: account.id, title: 'Semanal', frequency: 1, starts_at: Time.current,
                                         created_by_id: user.id, recipient_mode: 3, recipient_user_ids: [colega.id, user.id])

      user.destroy!

      expect([Crm::FollowUp.find(lembrete).created_by_id, Crm::FollowUpSeries.where(id: serie).pick(:created_by_id, :recipient_user_ids)])
        .to eq([administrador.id, [administrador.id, [colega.id]]])
    end
  end

  it 'sem administrador na conta, a reunião futura fica sem autor e a visão compartilhada sai' do
    futura = reuniao(user, card(colega))
    visao = linha(Crm::SavedView, account_id: account.id, user_id: user.id, name: 'Do time', visibility: 1)

    user.destroy!

    expect([Crm::Meeting.find(futura).created_by_id, Crm::SavedView.unscoped.exists?(visao)]).to eq([nil, false])
  end

  it 'quem sai não recebe o que é dela mesmo sendo a única administradora' do
    dona = create(:user, account: account, role: :administrator)
    visao = linha(Crm::SavedView, account_id: account.id, user_id: dona.id, name: 'Do time', visibility: 1)

    dona.destroy!

    expect(Crm::SavedView.unscoped.exists?(visao)).to be(false)
  end

  it 'refaz os contadores de quem vê o card depois do commit, por conta' do
    card(user)
    allow(Crm::Access::CountInvalidation).to receive(:card_changed!)

    user.destroy!

    expect(Crm::Access::CountInvalidation).to have_received(:card_changed!).with(account.id, []).once
  end

  it 'pelo DeleteObjectJob, que é o caminho de quem sai da última conta' do
    reuniao(user, card(user))

    DeleteObjectJob.perform_now(user)

    expect(User.exists?(user.id)).to be(false)
  end

  it 'manda a prévia do link de agendamento para o purge' do
    link = Crm::AgentBookingLink.find(linha(Crm::AgentBookingLink, account_id: account.id, booking_profile_id: pagina, agent_id: user.id,
                                                                   slug: 'agenda-pessoa'))
    link.preview_image.attach(io: StringIO.new('png'), filename: 'previa.png')

    user.destroy!

    expect(ActiveStorage::Attachment.where(record_type: 'Crm::AgentBookingLink', record_id: link.id)).to be_empty
  end
end
