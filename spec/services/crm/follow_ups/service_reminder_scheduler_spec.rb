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

  # Uma mensagem por vez por card (#1589): o follow-up automático em curso segura andamento e "deu certo?".
  describe 'com o follow-up automático no mesmo card' do
    def ligar_automatico(card, mode: 'auto_send')
      ai = card.pipeline.metadata['ai'].merge('auto_followup' => card.pipeline.metadata.dig('ai', 'auto_followup')
                                                                   .merge('enabled' => true, 'mode' => mode))
      card.pipeline.update!(metadata: card.pipeline.metadata.merge('ai' => ai))
    end

    def toque_automatico(card, enviado_em: nil)
      toque = account.crm_follow_ups.create!(
        card: card, conversation: card.primary_conversation, title: 'Retomar', due_at: now + 1.hour, timezone: 'UTC',
        automation_mode: :auto_send_message, created_by: user, metadata: { 'source' => 'ai_followup', 'touch' => 1, 'message_body' => 'Oi' }
      )
      return toque unless enviado_em

      toque.update_columns(status: Crm::FollowUp.statuses[:done], completed_at: enviado_em,
                           metadata: toque.metadata.merge('sent_message_id' => 1))
      toque
    end

    it 'toque pendente: o andamento não é criado, e o que já estava pendente é cancelado e volta depois' do
      card = setup_card
      card.update_columns(entered_stage_at: now - 2.days)
      ligar_automatico(card)
      expect(schedule(card)).to eq(1)
      lembrete = reminders(card).sole

      toque = toque_automatico(card)
      expect(described_class.wanted?(lembrete.reload, now: now)).to be(false)
      expect(schedule(card)).to eq(0)
      expect(lembrete.reload).to be_canceled

      toque.update_columns(status: Crm::FollowUp.statuses[:canceled])
      expect(schedule(card)).to eq(1)
    end

    it 'toque enviado há menos de 24 h segura o andamento e o "deu certo?"; passado o dia, saem' do
      card = setup_card
      card.update_columns(entered_stage_at: now - 3.days)
      ligar_automatico(card)
      toque_automatico(card, enviado_em: now - 20.hours)
      expect(schedule(card)).to eq(0)

      resolvido = setup_card(category: 'resolvido')
      resolvido.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now - 2.days)
      ligar_automatico(resolvido)
      toque_automatico(resolvido, enviado_em: now - 20.hours)
      expect(schedule(resolvido)).to eq(0)

      expect(schedule(card, at: now + 5.hours)).to eq(1)
      expect(schedule(resolvido, at: now + 5.hours)).to eq(1)
    end

    it 'cadência só de lembrete para a equipe (nada vai ao cliente) não segura o andamento' do
      card = setup_card
      card.update_columns(entered_stage_at: now - 2.days)
      ligar_automatico(card, mode: 'ai_reminder')
      toque_automatico(card)

      expect(schedule(card)).to eq(1)
    end

    it 'cadência desligada com toque parado não segura o andamento' do
      card = setup_card
      card.update_columns(entered_stage_at: now - 2.days)
      toque_automatico(card)

      expect(schedule(card)).to eq(1)
    end

    it 'o lembrete de pagamento da Cobrança não espera (tem dia marcado)' do
      card = setup_card(template: 'COBRANCA', category: 'novo', expected_close_at: Date.new(2026, 10, 17))
      ligar_automatico(card)
      toque_automatico(card)

      schedule(card)
      expect(reminders(card).map { |r| r.metadata['kind'] }).to contain_exactly('payment_before', 'payment_due', 'payment_after')
    end
  end

  it 'o job passa pelos funis de Atender e cria os lembretes' do
    card = setup_card
    card.update_columns(entered_stage_at: 2.days.ago)
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { Crm::ServiceRemindersJob.perform_now }

    expect(reminders(card).map { |r| r.metadata['kind'] }).to eq(['progress'])
  end

  # Às 21h em São Paulo (fora do horário 8–20 do funil) o espaçamento sumia: todos caíam juntos às 8h (CI de 00:00 UTC).
  it 'ao ligar num funil cheio, o job cria poucos por rodada e espaçados, mesmo fora do horário' do
    travel_to(Time.zone.parse('2026-10-15 00:00 UTC'))
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

  # #1589: o tempo de cada lembrete é escolhido no funil (metadata.ai.service_reminders.<lembrete>_after_hours).
  describe 'com o tempo escolhido no funil' do
    def escolher(card, horas)
      reminders = card.pipeline.metadata.dig('ai', 'service_reminders').to_h.merge(horas)
      card.pipeline.update!(metadata: card.pipeline.metadata.merge('ai' => card.pipeline.metadata['ai'].merge('service_reminders' => reminders)))
    end

    it 'andamento em 4 horas: sai com 4 h parado, e a conversa que andou há 5 h não segura' do
      card = setup_card
      escolher(card, 'progress_after_hours' => 4)
      card.update_columns(entered_stage_at: now - 6.hours, last_activity_at: now - 5.hours)

      expect(schedule(card)).to eq(1)
      expect(reminders(card).sole.metadata['after_hours']).to eq(4)
    end

    it 'andamento em 3 dias: com 2 dias parado, fica marcado para o 3º dia' do
      card = setup_card
      escolher(card, 'progress_after_hours' => 72)
      card.update_columns(entered_stage_at: now - 2.days)

      expect(schedule(card)).to eq(1)
      expect(reminders(card).sole.due_at).to be_within(1.minute).of(now + 1.day)
    end

    it '"deu certo?" em 1 semana sai 7 dias depois e ainda vale no 9º dia; valor fora da tela vira 1 dia' do
      card = setup_card
      escolher(card, 'resolved_check_after_hours' => 168)
      card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now - 2.hours)
      schedule(card)
      expect(reminders(card).sole.due_at).to be_within(1.minute).of(now - 2.hours + 7.days)

      card.update_columns(closed_at: now - 9.days)
      expect(described_class.new(card: card.reload, now: now).desired.map(&:kind)).to eq(['resolved_check'])

      escolher(card, 'resolved_check_after_hours' => 100)
      expect(Crm::Ai::Config.service_reminders_settings(card.pipeline.reload)[:resolved_check_after_hours]).to eq(24)
    end

    it 'mudou o tempo com o lembrete pendente: ele vai para o novo horário, sem lembrete novo' do
      card = setup_card
      card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now - 2.hours)
      schedule(card)
      lembrete = reminders(card).sole
      expect(lembrete.metadata['after_hours']).to eq(24)

      escolher(card, 'resolved_check_after_hours' => 72)
      expect(schedule(card)).to eq(1)
      expect(schedule(card)).to eq(0)

      expect(reminders(card).sole.id).to eq(lembrete.id)
      expect(lembrete.reload.due_at).to be_within(1.minute).of(now - 2.hours + 3.days)
      expect(lembrete.metadata['after_hours']).to eq(72)
    end

    it 'lembrete criado antes da escolha (sem o tempo gravado) conta como 1 dia e só muda se o tempo mudar' do
      card = setup_card
      card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now - 2.hours)
      schedule(card)
      lembrete = reminders(card).sole
      lembrete.update_columns(metadata: lembrete.metadata.except('after_hours'))
      antes = lembrete.reload.due_at

      expect(schedule(card)).to eq(0)
      expect(lembrete.reload.due_at).to eq(antes)
    end

    it 'andamento pendente também muda de horário; o que já saiu ou virou aviso para a equipe não é tocado' do
      card = setup_card
      escolher(card, 'progress_after_hours' => 72)
      card.update_columns(entered_stage_at: now - 2.days)
      schedule(card)
      pendente = reminders(card).sole

      escolher(card, 'progress_after_hours' => 48)
      expect(schedule(card)).to eq(1)
      expect(pendente.reload.due_at).to be_within(1.minute).of(now)

      %i[done overdue].each do |status|
        pendente.update_columns(status: Crm::FollowUp.statuses[status], due_at: now - 1.hour)
        escolher(card, 'progress_after_hours' => 4)
        expect(schedule(card)).to eq(0)
        expect(pendente.reload.due_at).to eq(now - 1.hour)
        escolher(card, 'progress_after_hours' => 48)
      end
    end

    it 'trocar o tempo num funil cheio leva os pendentes aos poucos e espaçados (teto e espaçamento do job)' do
      travel_to(now)
      cards = Array.new(3) do
        setup_card.tap { |card| card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now - 2.days) }
      end
      pipeline = cards.first.pipeline
      cards.drop(1).each { |card| card.update_columns(pipeline_id: pipeline.id, stage_id: cards.first.stage_id) }
      escolher(cards.first, 'resolved_check_after_hours' => 168)
      cards.each { |card| schedule(card) }

      escolher(cards.first, 'resolved_check_after_hours' => 24)
      stub_const('Crm::ServiceRemindersJob::MAX_NOVOS_POR_FUNIL', 2)
      with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { Crm::ServiceRemindersJob.perform_now }

      todos = Crm::FollowUp.where(card: cards).where("metadata ->> 'source' = ?", described_class::SOURCE)
      movidos = todos.select { |lembrete| lembrete.metadata['after_hours'] == 24 }.sort_by(&:due_at)
      expect(movidos.size).to eq(2)
      expect(movidos.last.due_at - movidos.first.due_at).to be >= described_class::STAGGER
      expect(todos.count { |lembrete| lembrete.metadata['after_hours'] == 168 }).to eq(1)
    end

    it 'com o "deu certo?" desligado, o job ainda cancela o andamento pendente do card que foi resolvido' do
      travel_to(now)
      card = setup_card
      escolher(card, 'resolved_check' => false)
      card.update_columns(entered_stage_at: now - 2.days)
      schedule(card)
      lembrete = reminders(card).sole
      card.update_columns(status: Crm::Card.statuses[:resolved], closed_at: now)

      with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { Crm::ServiceRemindersJob.perform_now }

      expect(lembrete.reload).to be_canceled
    end

    it 'com tudo desligado e só o tempo gravado, o job não passa pelos cards sem lembrete pendente' do
      card = setup_card
      card.update_columns(entered_stage_at: now - 2.days)
      escolher(card, 'progress' => false, 'resolved_check' => false, 'payment' => false, 'progress_after_hours' => 48)
      allow(described_class).to receive(:new).and_call_original

      with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { Crm::ServiceRemindersJob.perform_now }

      expect(described_class).not_to have_received(:new)
    end
  end

  it 'o job olha Resolvido de até 10 dias (1 semana + a folga)' do
    expect(Crm::ServiceRemindersJob::RESOLVED_LOOKBACK).to eq(10.days)
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

  # #2076: o título gravado do lembrete de pagamento fala como a conta (pacote do servidor, #1550): a corretora
  # diz "parcela". Conta sem pacote, ou de outro perfil, grava o texto base.
  describe 'título do lembrete de pagamento no pacote da conta' do
    let(:nicho) { Autonomia::Agents::Nicho }
    let(:pacote) { 'true' }
    let(:perfil) { 'corretora' }
    let(:locale) { 'pt_BR' }

    around do |example|
      GlobalConfig.clear_cache(nicho::PADRAO_KEY)
      with_modified_env(AUTONOMIA_PACOTES_ENABLED: pacote) { example.run }
    ensure
      GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    end

    before do
      account.update!(locale: locale, internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil })
    end

    def titulos
      card = setup_card(template: 'COBRANCA', category: 'novo', expected_close_at: Date.new(2026, 10, 20))
      schedule(card)
      reminders(card).to_h { |lembrete| [lembrete.metadata['kind'], lembrete.title] }
    end

    it 'corretora: "parcela" nos três avisos' do
      expect(titulos).to eq('payment_before' => 'Lembrar da parcela: 3 dias antes',
                            'payment_due' => 'Lembrar da parcela: no dia',
                            'payment_after' => 'Lembrar da parcela: depois do vencimento')
    end

    # A saúde diz "boleto" (#2083), como as telas do painel.
    describe 'com o perfil saude_beneficios' do
      let(:perfil) { 'saude_beneficios' }

      it 'grava o boleto' do
        expect(titulos.values).to contain_exactly('Lembrar do boleto: 3 dias antes', 'Lembrar do boleto: no dia',
                                                  'Lembrar do boleto: depois do vencimento')
      end
    end

    # Só a corretora diz "parcela" e a saúde, "boleto"; os outros perfis do nicho seguem com "pagamento".
    %w[seguradora insurtech].each do |outro_perfil|
      describe "com o perfil #{outro_perfil}" do
        let(:perfil) { outro_perfil }

        it 'grava o texto base' do
          expect(titulos.values).to contain_exactly('Lembrar do pagamento: 3 dias antes', 'Lembrar do pagamento: no dia',
                                                    'Lembrar do pagamento: depois do vencimento')
        end
      end
    end

    describe 'em inglês' do
      let(:locale) { 'en' }

      it 'corretora: "installment"' do
        expect(titulos['payment_due']).to eq('Installment reminder: on the day')
      end
    end

    describe 'com o interruptor de pacotes desligado' do
      let(:pacote) { nil }

      it 'grava o texto base' do
        expect(titulos['payment_before']).to eq('Lembrar do pagamento: 3 dias antes')
      end
    end

    describe 'em conta fora do nicho de seguros' do
      before { account.update!(internal_attributes: {}) }

      it 'grava o texto base' do
        expect(titulos['payment_before']).to eq('Lembrar do pagamento: 3 dias antes')
      end
    end

    it 'andamento segue neutro no pacote' do
      card = setup_card
      card.update_columns(entered_stage_at: now - 2.days)
      schedule(card)

      expect(reminders(card).sole.title).to eq('Avisar o andamento')
    end
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
