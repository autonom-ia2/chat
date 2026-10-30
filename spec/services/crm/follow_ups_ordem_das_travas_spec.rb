require 'rails_helper'
require 'timeout'

# Ordem das travas dos lembretes automáticos (#2100), com duas conexões reais: lembrete, depois card, como o
# DueProcessor e o Crm::Cards::Archiver. Cada exemplo falhava antes da correção.
RSpec.describe Crm::FollowUps, :crm_travas, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:funil) { create_crm_pipeline(account: account, user: admin) }
  let!(:card) { account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Pedido') }
  let(:pronto) { Queue.new }
  let(:soltar) { Queue.new }
  let(:resultados) { Queue.new }
  let(:conversa) do
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [admin])
    contato = account.contacts.create!(name: 'Carlos', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    create_crm_conversation(account: account, inbox: inbox, contact: contato, assignee: admin)
  end

  after do
    soltar << true
    crm_travas_threads.each { |thread| thread.join(1) || thread.kill.join }
  ensure
    apagar_crm_gravado(account)
    apagar_conversa_gravada
    apagar_conta_gravada(account, admin)
  end

  def apagar_conversa_gravada
    inboxes = Inbox.where(account_id: account.id).to_a
    [Message, Conversation].each { |modelo| modelo.where(account_id: account.id).delete_all }
    [ContactInbox, InboxMember].each { |modelo| modelo.where(inbox_id: inboxes.map(&:id)).delete_all }
    Contact.where(account_id: account.id).delete_all
    inboxes.each { |inbox| inbox.delete && inbox.channel&.delete }
  end

  # Lembrete automático na conversa de WhatsApp do card, como o job e o retorno combinado criam.
  def lembrete_automatico(metadata, due_at: 2.days.from_now)
    Crm::FollowUp.create!(account: account, card: card, conversation: conversa, contact: conversa.contact, inbox: conversa.inbox,
                          created_by: admin, assignee: admin, title: 'Lembrete', due_at: due_at, timezone: 'America/Sao_Paulo',
                          status: :pending, follow_up_type: :message, automation_mode: :auto_send_message,
                          metadata: metadata.merge('message_body' => 'Lembrete do atendimento.'))
  end

  # Para o Crm::Cards::Archiver dentro do método `metodo` (depois de chamá-lo) até `soltar`.
  def arquivamento_parado_em(arquivador, metodo)
    aviso = pronto
    espera = soltar
    allow(arquivador).to receive(metodo).and_wrap_original do |original, *args|
      original.call(*args).tap do
        aviso << true
        espera.pop
      end
    end
    em_outra_conexao(resultados) { arquivador.perform }
    pronto.pop
  end

  # service_reminder_scheduler.rb travava o card e depois o lembrete; o DueProcessor (due_processor.rb:19–22) trava o
  # lembrete e depois lê o card na barreira do arquivamento. As duas rotinas no mesmo card: ActiveRecord::Deadlocked.
  # Agora o job não espera o lembrete nem a barreira que o DueProcessor segura: deixa o lembrete para a rodada seguinte.
  it 'o job de lembretes de Atender e o DueProcessor no mesmo card terminam sem Deadlocked' do
    obsoleto = lembrete_automatico({ 'source' => Crm::FollowUps::ServiceReminderScheduler::SOURCE, 'kind' => 'progress', 'key' => 'progress:0:0' })
    aviso = pronto
    espera = soltar
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        Crm::FollowUp.find(obsoleto.id).lock!
        arquivado = Crm::Cards::Archiver.arquivado_sob_trava?(card.id)
        aviso << true
        espera.pop
        arquivado
      end
    end
    pronto.pop

    agendador = Crm::FollowUps::ServiceReminderScheduler.new(card: Crm::Card.find(card.id))
    # O DueProcessor segura o lembrete e a barreira do card (a IA e o envio): o job termina sem esperar por ele.
    esperar_fim_ou_trava(em_outra_conexao(resultados) { agendador.perform }, resultados, 0)
    expect(resultados.size).to eq(1)
    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to contain_exactly(false, 0)
    expect(obsoleto.reload).to be_pending
    Crm::FollowUps::ServiceReminderScheduler.new(card: Crm::Card.find(card.id)).perform
    expect(obsoleto.reload).to have_attributes(status: 'canceled')
    expect(obsoleto.metadata['canceled_reason']).to eq('no_longer_due')
  end

  # preflight.rb:65 segurava o lembrete sem a barreira: a 2ª passagem do arquivamento (SKIP LOCKED) o pulava e ele
  # ficava pendente no card arquivado, com o pré-voo seguindo (modelo novo na Meta para um card que não manda nada).
  it 'pré-voo no meio do arquivamento: espera na barreira e cancela o lembrete (card_archived)' do
    arquivador = Crm::Cards::Archiver.new(card: Crm::Card.find(card.id), actor: admin)
    primeira = true
    aviso = pronto
    espera = soltar
    allow(arquivador).to receive(:travar_lembretes).and_wrap_original do |original, *args|
      original.call(*args).tap do
        next unless primeira

        primeira = false
        aviso << true
        espera.pop
      end
    end
    no_card = Queue.new
    segue = Queue.new
    allow(arquivador).to receive(:series_novas).and_wrap_original do |original, *args|
      no_card << true
      segue.pop
      original.call(*args)
    end
    em_outra_conexao(resultados) { arquivador.perform }
    pronto.pop
    tardio = lembrete_automatico({ 'source' => Crm::FollowUps::CallbackScheduler::SOURCE }, due_at: 5.minutes.from_now)
    soltar << true
    no_card.pop

    esperar_na_trava(em_outra_conexao(resultados) { Crm::FollowUps::Preflight.new(follow_up: Crm::FollowUp.find(tardio.id)).call })
    segue << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to contain_exactly(true, nil)
    expect(card.reload).to be_archived
    expect(tardio.reload).to have_attributes(status: 'canceled')
    expect(tardio.metadata['canceled_reason']).to eq('card_archived')
    expect(tardio.metadata).not_to have_key('preflight')
  end

  # auto_followup_planner.rb:130/172 criava a 1ª vez e gravava `active: true` com o card lido antes do arquivamento.
  it 'a varredura do follow-up de IA espera o arquivamento e não arma a cadência no card arquivado' do
    card_aberto = Crm::Card.find(card.id)
    arquivamento_parado_em(Crm::Cards::Archiver.new(card: Crm::Card.find(card.id), actor: admin), :arquivar!)

    planejador = Crm::FollowUps::AutoFollowupPlanner.new(pipeline: funil.first)
    esperar_na_trava(em_outra_conexao(resultados) { planejador.send(:create_first_touch, card_aberto, 1.day.ago) })
    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to contain_exactly(true, nil)
    expect(card.reload).to be_archived
    expect(card.metadata.to_h.dig('ai', 'auto_followup_state', 'active')).not_to be(true)
    expect(Crm::FollowUp.where(card_id: card.id).where("metadata ->> 'source' = 'ai_followup'")).to be_empty
  end
end
