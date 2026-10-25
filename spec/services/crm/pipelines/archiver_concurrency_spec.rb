require 'rails_helper'
require 'timeout'

# Arquivar um funil (#2095) com duas conexões reais. A trava da conta era `accounts FOR UPDATE`: quem segurava um card do
# funil e ia gravar um filho da conta (retorno, atividade) esperava pela conta, enquanto o arquivamento, com a conta
# travada, esperava pelo card. Um dos dois terminava em ActiveRecord::Deadlocked.
RSpec.describe Crm::Pipelines::Archiver, :crm_travas, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:funil) { create_crm_pipeline(account: account, user: admin) }
  let!(:destino) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
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

  def novo_principal
    funil.first.reload.is_default? ? destino.first : nil
  end

  it 'arquivar movendo enquanto outro pedido segura o card e grava um retorno: os dois terminam, sem Deadlocked' do
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        Crm::Card.find(card.id).lock!
        pronto << true
        soltar.pop
        Crm::FollowUp.create!(account: account, card_id: card.id, created_by: admin, title: 'Ligar', due_at: 2.days.from_now,
                              timezone: 'America/Sao_Paulo', status: :pending)
      end
      true
    end
    pronto.pop
    arquivador = described_class.new(pipeline: Crm::Pipeline.find(funil.first.id), actor: admin, target_stage: destino.last,
                                     new_default: novo_principal)

    esperar_na_trava(em_outra_conexao(resultados) { arquivador.perform && true })
    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to eq([true, true])
    expect(funil.first.reload).to be_archived
    expect(card.reload.pipeline_id).to eq(destino.first.id)
    expect(card.follow_ups.count).to eq(1)
  end

  it 'arquivar não para a conta: outro pedido grava um card novo enquanto o arquivamento segura a trava' do
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        Crm::Pipelines::TravaDeArquivar.travar!(account.id)
        Crm::Pipeline.find(funil.first.id).lock!(described_class::TRAVA_DO_FUNIL)
        pronto << true
        soltar.pop
      end
      true
    end
    pronto.pop

    Timeout.timeout(5) { account.crm_cards.create!(pipeline: destino.first, stage: destino.last, title: 'Novo') }
    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 1)).to eq([true])
  end

  # #2145: num lote só, o card de cada cliente ficava travado até o fim do arquivamento. Em lotes, o card do lote que já
  # saiu fica livre enquanto o arquivamento ainda leva os outros.
  it 'mover em lotes: o card já levado pode ser mexido enquanto o arquivamento leva os outros' do
    stub_const("#{described_class}::LOTE", 1)
    segundo = account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Segundo')
    terceiro = account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Terceiro')
    aviso = pronto
    espera = soltar
    # Para no lote do segundo card, já movido e ainda não confirmado (as atividades do lote saem no fim dele). Num lote
    # só, essa vez não existia: o primeiro card estava no mesmo lote.
    allow(Crm::Activity).to receive(:insert_all!).and_wrap_original do |original, linhas, *resto|
      if linhas.map { |linha| linha[:card_id] } == [segundo.id]
        aviso << true
        espera.pop
      end
      original.call(linhas, *resto)
    end
    arquivador = described_class.new(pipeline: Crm::Pipeline.find(funil.first.id), actor: admin, target_stage: destino.last,
                                     new_default: novo_principal)
    em_outra_conexao(resultados) { arquivador.perform.moved.map(&:id) }
    Timeout.timeout(5) { pronto.pop }

    mexer = em_outra_conexao(resultados) { Crm::Card.find(card.id).update!(title: 'Mexido no meio') }
    esperar_fim_ou_trava(mexer, resultados, 0)
    expect(resultados.size).to eq(1)
    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to eq([true, [card.id, segundo.id, terceiro.id]])
    expect(funil.first.reload).to be_archived
    expect(account.crm_cards.where(id: [card.id, segundo.id, terceiro.id]).pluck(:pipeline_id).uniq).to eq([destino.first.id])
    expect(card.reload.title).to eq('Mexido no meio')
  end

  # Revisão do #2145: arquivar P1 levando para P2 e P2 levando para P1 ao mesmo tempo. Com a trava solta a cada lote e
  # os abertos relidos a cada lote, um devolvia cards ao outro sem fim. Lidos uma vez, cada um leva só os seus.
  it 'mover em lotes: dois arquivamentos cruzados terminam' do
    stub_const("#{described_class}::LOTE", 1)
    account.crm_pipelines.update_all(is_default: false) # rubocop:disable Rails/SkipsModelValidations
    create_crm_pipeline(account: account, user: admin, name: 'Principal').first.update_columns(is_default: true) # rubocop:disable Rails/SkipsModelValidations
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Outro de P1')
    2.times { |i| account.crm_cards.create!(pipeline: destino.first, stage: destino.last, title: "De P2 #{i}") }
    lotes = Concurrent::AtomicFixnum.new(0)
    primeiro = Queue.new
    espera = soltar
    allow(Crm::Activity).to receive(:insert_all!).and_wrap_original do |original, linhas, *resto|
      vez = lotes.increment
      raise 'lotes sem fim' if vez > 40

      if vez == 1
        primeiro << true
        espera.pop
      end
      original.call(linhas, *resto)
    end
    de_p1 = described_class.new(pipeline: Crm::Pipeline.find(funil.first.id), actor: admin, target_stage: destino.last)
    de_p2 = described_class.new(pipeline: Crm::Pipeline.find(destino.first.id), actor: admin, target_stage: funil.last)
    em_outra_conexao(resultados) { de_p1.perform.moved.size }
    Timeout.timeout(5) { primeiro.pop }
    esperar_na_trava(em_outra_conexao(resultados) { de_p2.perform.moved.size })
    soltar << true
    crm_travas_threads.each { |thread| thread.join(20) }

    # Um termina arquivando; o outro termina também, arquivando ou recusando o destino que o primeiro arquivou.
    fim = resultados_de(resultados, 2)
    expect(lotes.value).to be <= 6
    expect(fim.grep(Integer)).not_to be_empty
    expect(fim - fim.grep(Integer)).to all(eq('Crm::Pipelines::Archiver::InvalidTarget'))
  end

  it 'restaurar um card enquanto o funil dele é arquivado: espera e recusa, em vez de deixá-lo aberto no funil arquivado' do
    Crm::Cards::Archiver.new(card: card, actor: admin).perform
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        Crm::Pipelines::TravaDeArquivar.travar!(account.id)
        pipeline = Crm::Pipeline.find(funil.first.id)
        pipeline.lock!(described_class::TRAVA_DO_FUNIL)
        pronto << true
        soltar.pop
        pipeline.archived!
      end
      true
    end
    pronto.pop

    restaurador = Crm::Cards::Restorer.new(card: Crm::Card.find(card.id), actor: admin)
    esperar_na_trava(em_outra_conexao(resultados) { restaurador.perform.error })
    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to eq([true, Crm::Cards::Restorer::PIPELINE_ARCHIVED])
    expect(card.reload).to be_archived
  end

  # Re-revisão do #2097: o lote de restaurar segurava FOR SHARE no funil de cada card até o fim e esperava o funil que o
  # arquivamento travou; o arquivamento, movendo, esperava o funil de destino que o lote segurava. Um dos dois saía com
  # ActiveRecord::Deadlocked (e o DELETE respondia 500). A trava compartilhada de arquivar põe o lote atrás.
  it 'restaurar em lote enquanto o funil é arquivado movendo para o funil de outro card do lote: sem Deadlocked' do
    proposta = account.crm_pipeline_stages.create!(pipeline: destino.first, name: 'Proposta', position: 1)
    no_destino = account.crm_cards.create!(pipeline: destino.first, stage: destino.last, title: 'No destino')
    no_funil = account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'No funil')
    [no_destino, no_funil].each { |arquivado| Crm::Cards::Archiver.new(card: arquivado, actor: admin).perform }
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        Crm::PipelineStage.where(id: proposta.id).lock.load
        pronto << true
        soltar.pop
      end
      :etapa
    end
    pronto.pop
    arquivar = described_class.new(pipeline: Crm::Pipeline.find(funil.first.id), actor: admin, target_stage: proposta,
                                   new_default: novo_principal)
    esperar_na_trava(em_outra_conexao(resultados) { arquivar.perform && :arquivado })
    lote = Crm::Cards::BulkRestorer.new(account: account, user: admin, account_user: admin.account_users.first,
                                        ids: [no_destino.id, no_funil.id])
    esperar_na_trava(em_outra_conexao(resultados) { lote.perform })
    soltar << true
    crm_travas_threads.each(&:join)

    fim = resultados_de(resultados, 3)
    pulado = { id: no_funil.id, error: Crm::Cards::Restorer::PIPELINE_ARCHIVED }
    expect(fim).to include(:etapa, :arquivado, { restored: [no_destino.id], skipped: [pulado] })
    expect(fim).not_to include('ActiveRecord::Deadlocked')
  end
end
