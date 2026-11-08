require 'rails_helper'

# Reconciliação dos formulários (#2285): uma leitura por formulário com destino, por rodada, só onde a conta recebe.
RSpec.describe Crm::MetaAds::LeadForms::ReconcileScheduleJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let!(:form) do
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento',
                                 pipeline: pipeline, stage: stage)
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    account.enable_features!('meta_ads_formularios')
    Crm::MetaAdsPage.create!(account: account, page_id: '104882', leadgen_receiving: true)
  end

  it 'enfileira a releitura do formulário com destino na Página que a conta recebe' do
    expect { described_class.perform_now }.to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob).with(form.id).exactly(:once)
  end

  it 'rodada seguinte com o job anterior ainda na fila: não enfileira outra leitura do mesmo formulário' do
    described_class.perform_now

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
  end

  it 'fila atrasada por horas: o job anterior ainda na fila não ganha outro' do
    described_class.perform_now

    travel 5.hours do
      expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
    end
  end

  it 'formulário sem destino fica de fora' do
    form.update!(pipeline: nil, stage: nil)

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
  end

  it 'funil arquivado fica de fora' do
    pipeline.update!(status: :archived)

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
  end

  it 'Página parada nesta conta fica de fora, mesmo recebendo em outra conta' do
    Crm::MetaAdsPage.find_by(account: account).update!(leadgen_receiving: false)
    Crm::MetaAdsPage.create!(account: create(:account), page_id: '104882', leadgen_receiving: true)

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
  end

  it 'conta sem a flag fica de fora' do
    account.disable_features!('meta_ads_formularios')

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
  end
end
