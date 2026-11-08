require 'rails_helper'
require 'timeout'

# Apagar a etapa ao mesmo tempo que outra pessoa muda um card dela de funil, com duas conexões reais (revisão do #2094).
RSpec.describe Crm::PipelineStages::Destroyer, :crm_travas, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:soltar) { Queue.new }

  after do
    soltar << true
    crm_travas_threads.each { |thread| thread.join(1) || thread.kill.join }
  ensure
    apagar_conta_gravada(account, admin)
  end

  it 'o card levado para outro funil enquanto isso fica onde foi posto, sem a atividade de etapa apagada' do
    origem = create_crm_stage(account: account, pipeline: funil.first, name: 'Sai', position: 2)
    fica = account.crm_cards.create!(pipeline: funil.first, stage: origem, title: 'Fica')
    muda = account.crm_cards.create!(pipeline: funil.first, stage: origem, title: 'Muda')
    outro_funil, outra_etapa = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')
    resultados = Queue.new
    pronto = Queue.new
    espera = soltar
    em_outra_conexao(resultados) do
      Crm::Card.transaction do
        Crm::Card.lock.find(muda.id).update!(pipeline: outro_funil, stage: outra_etapa)
        pronto << true
        espera.pop
      end
      true
    end
    pronto.pop

    apagando = em_outra_conexao(resultados) do
      described_class.new(stage: Crm::PipelineStage.find(origem.id), target_stage_id: funil.last.id, actor: admin).perform
    end
    esperar_na_trava(apagando)
    soltar << true
    crm_travas_threads.each(&:join)

    expect(resultados_de(resultados, 2)).to contain_exactly(true, described_class::SUCCESS)
    expect(muda.reload).to have_attributes(pipeline_id: outro_funil.id, stage_id: outra_etapa.id)
    expect(fica.reload.stage_id).to eq(funil.last.id)
    expect(Crm::Activity.where(card_id: muda.id, event_type: 'move')).to be_empty
    expect(Crm::Activity.where(card_id: fica.id, event_type: 'move').count).to eq(1)
  end
end
