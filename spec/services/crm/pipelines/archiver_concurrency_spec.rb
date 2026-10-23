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
end
