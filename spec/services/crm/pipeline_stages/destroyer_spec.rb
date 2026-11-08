require 'rails_helper'

RSpec.describe Crm::PipelineStages::Destroyer do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:etapa) { create_crm_stage(account: account, pipeline: funil.first, name: 'Sem uso', position: 2) }
  let(:card) { account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Pedido') }

  it 'apaga a etapa cuja automação já rodou, levando junto o registro das execuções' do
    automacao = account.crm_stage_automations.create!(pipeline: funil.first, stage: etapa, name: 'Avisar', trigger_event: :on_enter)
    Crm::StageAutomationExecution.create!(account: account, card: card, stage_automation: automacao, trigger_token: 't1')

    expect(described_class.new(stage: etapa).perform).to eq(described_class::SUCCESS)
    expect(Crm::PipelineStage.exists?(etapa.id)).to be(false)
  end

  it 'outro registro preso à etapa não vira "ainda tem cards"' do
    allow(etapa).to receive(:destroy!).and_raise(ActiveRecord::InvalidForeignKey, 'fk')

    expect(described_class.new(stage: etapa).perform).to eq(described_class::IN_USE)
  end

  it 'card preso à etapa continua "ainda tem cards"' do
    card
    expect(described_class.new(stage: funil.last).perform).to eq(described_class::HAS_CARDS)
  end

  it 'move os cards em lote, sem uma consulta por card' do
    3.times { |n| account.crm_cards.create!(pipeline: funil.first, stage: etapa, title: "Card #{n}") }
    destino = funil.last

    consultas = 0
    contador = ->(*, payload) { consultas += 1 if payload[:sql].lstrip.upcase.start_with?('UPDATE', 'INSERT') }
    ActiveSupport::Notifications.subscribed(contador, 'sql.active_record') do
      expect(described_class.new(stage: etapa, target_stage_id: destino.id, actor: admin).perform).to eq(described_class::SUCCESS)
    end

    expect(account.crm_cards.where(stage_id: destino.id).count).to eq(3)
    expect(Crm::Activity.where(account_id: account.id, event_type: 'move').count).to eq(3)
    expect(consultas).to be <= 6
  end
end
