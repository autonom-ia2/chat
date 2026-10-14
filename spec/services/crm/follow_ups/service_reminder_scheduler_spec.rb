require 'rails_helper'

# Os cenários montam datas no passado (entrada na etapa, fechamento) sem passar pelos callbacks que as regravam.
# rubocop:disable Rails/SkipsModelValidations

# Lembretes de Atender (#1498): andamento, "deu tudo certo?" e pagamento da Cobrança, por data, no motor do retorno.
RSpec.describe Crm::FollowUps::ServiceReminderScheduler do
  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:now) { Time.zone.parse('2026-10-14 15:00 UTC') }

  # Funil de Atender criado por modelo, conversa de WhatsApp, horário liberado o dia todo.
  def setup_card(template: 'ATENDIMENTO', category: 'andamento', **attrs)
    conversation = whatsapp_conversation
    pipeline, stage = atender_pipeline(template, category)
    card = account.crm_cards.create!({ pipeline: pipeline, stage: stage, inbox: conversation.inbox, contact: conversation.contact,
                                       primary_conversation: conversation, owner: user, title: 'Troca de tamanho' }.merge(attrs))
    # Sem novidade há dias: o aviso de andamento só sai quando a conversa parou.
    card.update_columns(last_activity_at: [now, Time.current].min - 3.days)
    card
  end

  def whatsapp_conversation
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Carlos', phone_number: "+55119#{rand(10_000_000..99_999_999)}",
                                       additional_attributes: { 'timezone' => 'America/Sao_Paulo' })
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    conversation
  end

  def atender_pipeline(template, category)
    pipeline, stage = create_crm_pipeline(account: account, user: user, name: 'Suporte')
    horario = { 'allowed_days' => (0..6).to_a, 'quiet_hours' => { 'start' => 8, 'end' => 20 } }
    ai = (pipeline.metadata['ai'] || {}).merge('auto_followup' => horario)
    pipeline.update!(counts_as_sale: false, metadata: pipeline.metadata.merge('template' => template, 'ai' => ai))
    stage.update!(metadata: { 'category' => category })
    [pipeline, stage]
  end

  def schedule(card, at: now)
    described_class.new(card: card.reload, now: at).perform
  end

  def reminders(card)
    Crm::FollowUp.where(card: card).where("metadata ->> 'source' = ?", described_class::SOURCE)
  end

  it 'avisa o andamento 1 dia depois de entrar na etapa, uma vez só' do
    card = setup_card
    card.update_columns(entered_stage_at: now - 2.days)

    expect(schedule(card)).to eq(1)
    expect(schedule(card)).to eq(0)

    lembrete = reminders(card).sole
    expect(lembrete.metadata['kind']).to eq('progress')
    expect(lembrete).to be_auto_send_message
    expect(lembrete.title).to be_present
  end

  it 'não avisa o andamento quando a conversa andou no último dia' do
    card = setup_card
    card.update_columns(entered_stage_at: now - 2.days, last_activity_at: now - 2.hours)

    expect(schedule(card)).to eq(0)
  end

  it 'nada para quem recusou mensagem automática nem para card arquivado, e cancela o que estava pendente' do
    card = setup_card
    card.update_columns(entered_stage_at: now - 2.days)
    expect(schedule(card)).to eq(1)

    card.primary_conversation.contact.update_columns(opted_out_at: now)
    expect(schedule(card)).to eq(0)
    expect(reminders(card).active).to be_empty
    expect(schedule(card)).to eq(0)
  end

  it 'andamento fora das 24h do WhatsApp (sem Híbrido) não é criado: ainda não há modelo para ele' do
    card = setup_card
    card.update_columns(entered_stage_at: now - 2.days)
    fechada = instance_double(Crm::FollowUps::MessagingWindow, whatsapp_capable?: true, can_send_session_message?: false,
                                                               hybrid_web_available?: false)
    allow(Crm::FollowUps::MessagingWindow).to receive(:new).and_return(fechada)

    expect(schedule(card)).to eq(0)
  end

  it 'lembrete de pagamento que o horário empurrou (sábado) continua valendo depois do dia; de dois atrasados, só o último' do
    card = setup_card(template: 'COBRANCA', category: 'novo', expected_close_at: Date.new(2026, 10, 17))
    schedule(card, at: Time.zone.parse('2026-10-14 15:00 UTC'))
    antes = reminders(card).find { |r| r.metadata['kind'] == 'payment_before' }
    no_dia = reminders(card).find { |r| r.metadata['kind'] == 'payment_due' }

    segunda = Time.zone.parse('2026-10-19 12:00 UTC')
    expect(described_class.wanted?(no_dia, now: segunda)).to be(true)
    expect(described_class.wanted?(antes, now: segunda)).to be(false)
  end

  it 'quando o "depois" chega e o "no dia" ainda espera o horário, só o "depois" vale' do
    card = setup_card(template: 'COBRANCA', category: 'novo', expected_close_at: Date.new(2026, 10, 16))
    schedule(card, at: Time.zone.parse('2026-10-14 15:00 UTC'))
    no_dia = reminders(card).find { |r| r.metadata['kind'] == 'payment_due' }

    expect(described_class.wanted?(no_dia, now: Time.zone.parse('2026-10-19 12:00 UTC'))).to be(false)
  end

  it 'o job passa pelos funis de Atender e cria os lembretes' do
    card = setup_card
    card.update_columns(entered_stage_at: 2.days.ago)
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { Crm::ServiceRemindersJob.perform_now }

    expect(reminders(card).map { |r| r.metadata['kind'] }).to eq(['progress'])
  end

  it 'ao ligar num funil cheio, o job cria poucos por rodada e espaçados' do
    cards = Array.new(3) { setup_card.tap { |card| card.update_columns(entered_stage_at: 2.days.ago) } }
    pipeline = cards.first.pipeline
    cards.drop(1).each { |card| card.update_columns(pipeline_id: pipeline.id, stage_id: cards.first.stage_id) }
    stub_const('Crm::ServiceRemindersJob::MAX_NOVOS_POR_FUNIL', 2)

    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { Crm::ServiceRemindersJob.perform_now }

    criados = Crm::FollowUp.where(card: cards).where("metadata ->> 'source' = ?", described_class::SOURCE).order(:due_at)
    expect(criados.size).to eq(2)
    expect(criados.last.due_at - criados.first.due_at).to be >= described_class::STAGGER

    # Com o teto, a rodada seguinte ainda cancela o que deixou de valer.
    criados.first.card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: Time.current)
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { Crm::ServiceRemindersJob.perform_now }
    expect(criados.first.reload).to be_canceled
  end

  it 'não avisa o andamento enquanto espera o cliente (a pausa)' do
    card = setup_card(category: 'espera')
    card.update_columns(entered_stage_at: now - 2.days)

    expect(schedule(card)).to eq(0)
  end

  it 'pergunta se resolveu 1 dia depois de Resolvido' do
    card = setup_card
    card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now - 2.hours)

    schedule(card)

    lembrete = reminders(card).sole
    expect(lembrete.metadata['kind']).to eq('resolved_check')
    expect(lembrete.due_at).to be_within(1.minute).of(now - 2.hours + 1.day)
  end

  it 'lembra do pagamento 3 dias antes, no dia e depois; o depois espera a promessa' do
    card = setup_card(template: 'COBRANCA', category: 'novo', value_cents: 35_000, expected_close_at: Date.new(2026, 10, 20))
    card.update!(metadata: { 'payment_promise_at' => '2026-10-27' })

    schedule(card)

    expect(reminders(card).map { |r| r.metadata['key'] }).to contain_exactly(
      'payment_before:2026-10-17', 'payment_due:2026-10-20', 'payment_after:2026-10-28'
    )
    no_dia = reminders(card).find { |r| r.metadata['kind'] == 'payment_due' }
    expect(no_dia.due_at.in_time_zone('America/Sao_Paulo').hour).to eq(8)
  end

  it 'não cria lembrete de dia que já passou' do
    card = setup_card(template: 'COBRANCA', category: 'novo', expected_close_at: Date.new(2026, 10, 12))

    schedule(card)

    expect(reminders(card).map { |r| r.metadata['kind'] }).to eq(['payment_after'])
  end

  it 'cancela o que deixou de valer quando o card fecha e confere de novo no envio' do
    card = setup_card(template: 'COBRANCA', category: 'novo', expected_close_at: Date.new(2026, 10, 20))
    schedule(card)
    lembrete = reminders(card).first

    card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now)
    expect(described_class.wanted?(lembrete.reload, now: now)).to be(false)

    schedule(card)
    expect(reminders(card).active).to be_empty
  end

  it 'fica desligado em funil de Atender antigo (sem modelo), até alguém ligar' do
    card = setup_card(template: nil)
    card.update_columns(entered_stage_at: now - 2.days)

    expect(schedule(card)).to eq(0)

    ai = card.pipeline.metadata['ai'].merge('service_reminders' => { 'progress' => true })
    card.pipeline.update!(metadata: card.pipeline.metadata.merge('ai' => ai))
    expect(schedule(card)).to eq(1)
  end

  it 'nunca age em funil de Vender' do
    card = setup_card
    card.pipeline.update!(counts_as_sale: true)
    card.update_columns(entered_stage_at: now - 2.days)

    expect(schedule(card)).to eq(0)
  end

  describe 'no envio (DueProcessor)' do
    around do |example|
      previous = %w[CRM_KANBAN_ENABLED CRM_AI_ENABLED].index_with { |key| ENV.fetch(key, nil) }
      previous.each_key { |key| ENV[key] = 'true' }
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it 'entrega pelo CallbackRunner o lembrete que ainda vale' do
      card = setup_card
      card.update_columns(entered_stage_at: 2.days.ago)
      described_class.new(card: card.reload).perform
      lembrete = reminders(card).sole
      runner = instance_double(Crm::FollowUps::CallbackRunner, perform: Crm::FollowUps::CallbackRunner::Result.sent)
      allow(Crm::FollowUps::CallbackRunner).to receive(:new).and_return(runner)

      Crm::FollowUps::DueProcessor.new(now: lembrete.due_at + 1.minute).perform

      expect(Crm::FollowUps::CallbackRunner).to have_received(:new).with(follow_up: lembrete, now: anything)
      expect(lembrete.reload).to be_done
    end

    it 'quando não sai, vira aviso para a equipe com o motivo em linguagem simples' do
      card = setup_card
      card.update_columns(entered_stage_at: 2.days.ago)
      described_class.new(card: card.reload).perform
      lembrete = reminders(card).sole
      fallback = Crm::FollowUps::CallbackRunner::Result.fallback('modelo_indisponivel:recusado')
      allow(Crm::FollowUps::CallbackRunner).to receive(:new).and_return(instance_double(Crm::FollowUps::CallbackRunner, perform: fallback))

      Crm::FollowUps::DueProcessor.new(now: lembrete.due_at + 1.minute).perform

      expect(lembrete.reload).to be_reminder_only
      expect(lembrete.description).to include('recusou o modelo').or include('rejected the message template')
    end

    # Decisão do Rodrigo (14/10, opção a): o "deu tudo certo?" que vira aviso para a equipe não reabre a conversa.
    it '"deu tudo certo?" que vira aviso para a equipe não reabre a conversa resolvida', :aggregate_failures do
      card = setup_card
      card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: 2.days.ago)
      described_class.new(card: card.reload).perform
      lembrete = reminders(card).sole
      card.primary_conversation.resolved!
      fallback = Crm::FollowUps::CallbackRunner::Result.fallback('modelo_indisponivel:em_analise')
      allow(Crm::FollowUps::CallbackRunner).to receive(:new).and_return(instance_double(Crm::FollowUps::CallbackRunner, perform: fallback))

      Crm::FollowUps::DueProcessor.new(now: lembrete.due_at + 1.minute).perform

      expect(lembrete.metadata['kind']).to eq('resolved_check')
      expect(lembrete.reload).to be_reminder_only
      expect(card.primary_conversation.reload).to be_resolved
    end

    it 'cliente que pediu para não receber: cancela calado, sem aviso para a equipe' do
      card = setup_card
      card.update_columns(entered_stage_at: 2.days.ago)
      described_class.new(card: card.reload).perform
      lembrete = reminders(card).sole
      fallback = Crm::FollowUps::CallbackRunner::Result.fallback(Crm::FollowUps::MessageSender::OPTED_OUT_REASON)
      allow(Crm::FollowUps::CallbackRunner).to receive(:new).and_return(instance_double(Crm::FollowUps::CallbackRunner, perform: fallback))

      Crm::FollowUps::DueProcessor.new(now: lembrete.due_at + 1.minute).perform

      expect(lembrete.reload).to be_canceled
      expect(lembrete).to be_auto_send_message
    end

    it 'cancela sem mandar o lembrete que deixou de valer' do
      card = setup_card
      card.update_columns(entered_stage_at: 2.days.ago)
      described_class.new(card: card.reload).perform
      lembrete = reminders(card).sole
      card.update_columns(entered_stage_at: Time.current)
      allow(Crm::FollowUps::CallbackRunner).to receive(:new)

      Crm::FollowUps::DueProcessor.new(now: lembrete.due_at + 1.minute).perform

      expect(Crm::FollowUps::CallbackRunner).not_to have_received(:new)
      expect(lembrete.reload).to be_canceled
    end
  end
end
# rubocop:enable Rails/SkipsModelValidations
