require 'rails_helper'
require 'timeout'

# Arquivar ao mesmo tempo que outro processo mexe no card, com duas conexões reais (revisão do #2094): o desfecho
# fechado por outro pedido, a ordem das travas do DueProcessor (lembrete, depois card) e a série que cria a vez seguinte.
RSpec.describe Crm::Cards::Archiver, :crm_travas, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:funil) { create_crm_pipeline(account: account, user: admin) }
  let!(:card) { account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Pedido') }
  let(:pronto) { Queue.new }
  let(:soltar) { Queue.new }
  let(:resultados) { Queue.new }

  after do
    soltar << true
    crm_travas_threads.each { |thread| thread.join(1) || thread.kill.join }
  ensure
    apagar_conta_gravada(account, admin)
  end

  def lembrete(**attrs)
    Crm::FollowUp.create!({ account: account, card: card, created_by: admin, title: 'Ligar', due_at: 2.days.from_now,
                            timezone: 'America/Sao_Paulo', status: :pending }.merge(attrs))
  end

  # Outra conexão faz `antes` numa transação, avisa e segura as travas até `soltar`; então faz `depois` e confirma.
  def outro_processo(antes:, depois: -> {})
    aviso = pronto
    espera = soltar
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        antes.call
        aviso << true
        espera.pop
        depois.call
      end
      true
    end
    pronto.pop
  end

  def arquivar_noutra_conexao(arquivador)
    esperar_na_trava(em_outra_conexao(resultados) { arquivador.perform })
    soltar << true
    crm_travas_threads.each(&:join)
  end

  it 'card fechado como Ganho por outro pedido enquanto o arquivamento esperava: o desfecho fica guardado' do
    carregado_antes = Crm::Card.find(card.id)
    outro_processo(antes: -> { Crm::Cards::Closer.new(card: Crm::Card.find(card.id), actor: admin, result: 'won').perform })

    arquivar_noutra_conexao(described_class.new(card: carregado_antes, actor: admin))

    expect(resultados_de(resultados, 2)).to eq([true, true])
    expect(card.reload).to have_attributes(status: 'archived', desfecho_arquivado: 'won', closed_at: be_present)
    expect(Crm::Card.com_desfecho(:won)).to include(card)
  end

  # due_processor.rb:19 trava o lembrete; auto_followup_runner.rb:117 trava o card depois. Na ordem inversa (card, depois
  # lembrete) o arquivamento e o DueProcessor terminavam um deles em ActiveRecord::Deadlocked.
  it 'arquivar enquanto o DueProcessor segura o lembrete termina sem Deadlocked' do
    retorno = lembrete
    outro_processo(antes: -> { Crm::FollowUp.find(retorno.id).lock! }, depois: -> { Crm::Card.find(card.id).lock! })

    arquivar_noutra_conexao(described_class.new(card: Crm::Card.find(card.id), actor: admin))

    expect(resultados_de(resultados, 2)).to eq([true, true])
    expect(card.reload).to be_archived
    expect(retorno.reload).to be_canceled
  end

  # O SeriesMaterializer trava a série e cria a vez seguinte quando não há vez pendente. Entre cancelar as vezes e
  # encerrar a série, ele criava uma vez nova num card arquivado.
  it 'a série que repete não ganha vez nova no meio do arquivamento' do
    serie = Crm::FollowUpSeries.create!(account: account, card: card, created_by: admin, title: 'Toda segunda', frequency: :weekly,
                                        starts_at: 2.weeks.ago, timezone: 'America/Sao_Paulo', weekdays: [1])
    lembrete(series: serie, status: :overdue, due_at: 1.week.ago, occurrence_at: 1.week.ago)
    arquivador = described_class.new(card: Crm::Card.find(card.id), actor: admin)
    aviso = pronto
    espera = soltar
    allow(arquivador).to receive(:cancelar_lembretes!).and_wrap_original do |original, *args|
      original.call(*args).tap do
        aviso << true
        espera.pop
      end
    end
    em_outra_conexao(resultados) { arquivador.perform }
    pronto.pop

    esperar_na_trava(em_outra_conexao(resultados) { Crm::FollowUps::SeriesMaterializer.new(Crm::FollowUpSeries.find(serie.id)).perform })
    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to include(true)
    expect(serie.reload).to be_ended
    expect(Crm::FollowUp.where(card_id: card.id).active).to be_empty
  end

  # Arquivamento parado depois de travar os lembretes e antes de travar o card.
  def arquivamento_parado_antes_do_card
    arquivador = described_class.new(card: Crm::Card.find(card.id), actor: admin)
    aviso = pronto
    espera = soltar
    primeira = true
    allow(arquivador).to receive(:travar_lembretes).and_wrap_original do |original, *args|
      original.call(*args).tap do
        next unless primeira

        primeira = false
        aviso << true
        espera.pop
      end
    end
    pid = em_outra_conexao(resultados) { arquivador.perform }
    pronto.pop
    pid
  end

  # creator.rb cria um lembrete já vencido no meio do arquivamento; due_processor.rb:19 o trava e depois quer o card
  # (CardNextDueUpdater). Travar lembrete depois do card fechava o ciclo.
  it 'lembrete vencido criado no meio do arquivamento: sem Deadlocked, e o DueProcessor o cancela depois' do
    arquivando = arquivamento_parado_antes_do_card
    tardio = lembrete(due_at: 1.minute.ago)
    due = Queue.new
    segura_card = Queue.new
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        Crm::FollowUp.find(tardio.id).lock!
        due << true
        segura_card.pop
        Crm::Card.find(card.id).lock!
      end
      true
    end
    due.pop

    soltar << true
    esperar_fim_ou_trava(arquivando, resultados, 0)
    segura_card << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to eq([true, true])
    expect(card.reload).to be_archived
    Crm::FollowUps::DueProcessor.new.perform
    expect(tardio.reload).to have_attributes(status: 'canceled')
    expect(tardio.metadata['canceled_reason']).to eq('card_archived')
  end

  # internal_creator.rb:45–51 marca a reunião e cria o lembrete dela no meio do arquivamento.
  it 'reunião marcada no meio do arquivamento fica, com o lembrete, e entra em reunioes_mantidas' do
    arquivamento_parado_antes_do_card
    reuniao = account.crm_meetings.new(card: card, created_by: admin, title: 'Conversa', provider: :internal, status: :draft,
                                       online_meeting_type: :whatsapp_video, timezone: 'America/Sao_Paulo',
                                       starts_at: 3.days.from_now, ends_at: 3.days.from_now + 30.minutes, source: 'public_link')
    reuniao.save!(validate: false)
    reuniao.meeting_guests.create!(account: account, email: 'cliente@exemplo.invalid', guest_type: :external_email)
    reuniao.update!(status: :scheduled, reminder: lembrete(follow_up_type: :meeting, due_at: 3.days.from_now - 15.minutes))

    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 1)).to eq([true])
    expect(reuniao.reminder.reload).to be_pending
    expect(card.activities.where(event_type: 'archive').last.payload).to include('reunioes_mantidas' => [reuniao.id])
    Crm::FollowUps::DueProcessor.new(now: 3.days.from_now - 10.minutes).perform
    expect(reuniao.reminder.reload).not_to be_canceled
  end

  it 'série criada no meio do arquivamento se encerra no Materializer, sem vez nova' do
    arquivamento_parado_antes_do_card
    serie = Crm::FollowUpSeries.create!(account: account, card: card, created_by: admin, title: 'Toda segunda', frequency: :weekly,
                                        starts_at: 1.day.from_now, timezone: 'America/Sao_Paulo', weekdays: [1])
    soltar << true
    crm_travas_threads.each(&:join)

    expect(Crm::FollowUps::SeriesMaterializer.new(serie).perform).to be_nil
    expect(serie.reload).to be_ended
  end

  # Lembrete vencido criado entre as travas dos lembretes e do card; o arquivamento segue até ficar com o card travado e
  # para de novo antes de gravar. O DueProcessor real roda nesse meio (due_processor.rb:19–23 lia o card sem trava e
  # o via aberto).
  it 'DueProcessor durante o arquivamento não dispara o lembrete tardio: ele termina cancelado (card_archived)' do
    arquivador = described_class.new(card: Crm::Card.find(card.id), actor: admin)
    no_card = Queue.new
    segue = Queue.new
    allow(arquivador).to receive(:arquivar!).and_wrap_original do |original, *args|
      no_card << true
      segue.pop
      original.call(*args)
    end
    aviso = pronto
    espera = soltar
    allow(arquivador).to receive(:travar_lembretes).and_wrap_original do |original, *args|
      original.call(*args).tap do
        aviso << true
        espera.pop
      end
    end
    em_outra_conexao(resultados) { arquivador.perform }
    pronto.pop
    tardio = lembrete(due_at: 1.minute.ago)
    soltar << true
    no_card.pop

    esperar_na_trava(em_outra_conexao(resultados) { Crm::FollowUps::DueProcessor.new.perform })
    segue << true
    crm_travas_threads.each(&:join)

    expect(card.reload).to be_archived
    expect(tardio.reload).to have_attributes(status: 'canceled')
    expect(tardio.metadata['canceled_reason']).to eq('card_archived')
  end

  # follow_up_series_materializer_job.rb / creator.rb: série e a 1ª vez criadas entre as travas e o card.
  it 'série e a primeira vez criadas entre as travas e o card são encerrada e cancelada pelo arquivamento' do
    arquivamento_parado_antes_do_card
    serie = Crm::FollowUpSeries.create!(account: account, card: card, created_by: admin, title: 'Toda segunda', frequency: :weekly,
                                        starts_at: 1.day.from_now, timezone: 'America/Sao_Paulo', weekdays: [1])
    primeira = Crm::FollowUps::SeriesMaterializer.new(serie).perform

    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 1)).to eq([true])
    expect(serie.reload).to be_ended
    expect(primeira.reload).to be_canceled
  end

  # #2101/#2130: a pessoa pede o lembrete com o card ainda aberto (o Creator conferiu), e o arquivamento já segura o
  # card FOR UPDATE. A criação espera na trava do card e, quando o arquivamento confirma, recusa sem gravar nada.
  describe 'lembrete pedido por pessoa enquanto o arquivamento segura o card' do
    def arquivamento_parado_com_o_card_travado
      arquivador = described_class.new(card: Crm::Card.find(card.id), actor: admin)
      aviso = pronto
      espera = soltar
      allow(arquivador).to receive(:arquivar!).and_wrap_original do |original, *args|
        original.call(*args).tap do
          aviso << true
          espera.pop
        end
      end
      em_outra_conexao(resultados) { arquivador.perform }
      pronto.pop
    end

    def criar_noutra_conexao(card_aberto, **extra)
      atributos = { title: 'Ligar', due_at: 2.days.from_now.iso8601, timezone: 'America/Sao_Paulo',
                    automation_mode: 'reminder_only', follow_up_type: 'task' }.merge(extra).with_indifferent_access
      criador = Crm::FollowUps::Creator.new(account: account, user: admin, card: card_aberto, conversation: nil, attributes: atributos)
      esperar_na_trava(em_outra_conexao(resultados) { criador.perform })
    end

    # Solta o arquivamento e devolve o que as duas conexões responderam.
    def soltar_e_ler_respostas
      soltar << true
      crm_travas_threads.each(&:join)
      resultados_de(resultados, 2)
    end

    def gravados = { series: Crm::FollowUpSeries.where(card_id: card.id).count, lembretes: Crm::FollowUp.where(card_id: card.id).count }

    it 'o lembrete de uma vez espera e é recusado (CardArchived), sem lembrete gravado' do
      card_aberto = Crm::Card.find(card.id)
      arquivamento_parado_com_o_card_travado

      criar_noutra_conexao(card_aberto)

      expect(soltar_e_ler_respostas).to contain_exactly(true, 'Crm::FollowUps::Creator::CardArchived')
      expect(card.reload).to be_archived
      expect(gravados).to eq(series: 0, lembretes: 0)
    end

    it 'a série espera e é recusada (CardArchived), sem série nem vez gravadas' do
      card_aberto = Crm::Card.find(card.id)
      arquivamento_parado_com_o_card_travado

      criar_noutra_conexao(card_aberto, recurrence: { frequency: 'weekly', weekdays: [1] })

      expect(soltar_e_ler_respostas).to contain_exactly(true, 'Crm::FollowUps::Creator::CardArchived')
      expect(card.reload).to be_archived
      expect(gravados).to eq(series: 0, lembretes: 0)
    end
  end
end
