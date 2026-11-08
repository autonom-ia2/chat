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
                                 pipeline: pipeline, stage: stage, destination_set_at: 1.day.ago)
  end
  let!(:page) { Crm::MetaAdsPage.create!(account: account, page_id: '104882', leadgen_receiving: true, leadgen_receiving_since: 1.day.ago) }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    account.enable_features!('meta_ads_formularios')
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
    page.update!(leadgen_receiving: false, leadgen_receiving_since: nil)
    Crm::MetaAdsPage.create!(account: create(:account), page_id: '104882', leadgen_receiving: true, leadgen_receiving_since: 1.day.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
  end

  it 'formulário sem marco de destino (linha de antes do #2285) fica de fora' do
    form.update!(destination_set_at: nil)

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
  end

  it 'Página sem marco fica de fora' do
    page.update!(leadgen_receiving_since: nil)

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
  end

  it 'conta sem a flag fica de fora, e o marco da Página anda: o período sem flag não é relido' do
    account.disable_features!('meta_ads_formularios')

    freeze_time do
      expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob)
      expect(page.reload.leadgen_receiving_since).to eq(Time.current)
    end
  end

  it 'flag de volta: a releitura começa na última rodada com a flag desligada' do
    account.disable_features!('meta_ads_formularios')
    paused_at = Time.current.change(usec: 0)
    travel_to(paused_at) { described_class.perform_now }
    account.enable_features!('meta_ads_formularios')

    travel_to(paused_at + 1.hour) do
      expect { described_class.perform_now }.to have_enqueued_job(Crm::MetaAds::LeadForms::ReconcileJob).with(form.id)
      expect(page.reload.leadgen_receiving_since).to eq(paused_at)
    end
  end

  it 'flag desligada noutra conta não mexe no marco desta' do
    other = create(:account)
    other.disable_features!('meta_ads_formularios')
    other_pipeline, other_stage = create_crm_pipeline(account: other, user: create(:user, account: other, role: :administrator))
    Crm::MetaAdsLeadForm.create!(account: other, page_id: '104882', form_id: '9001', pipeline: other_pipeline, stage: other_stage,
                                 destination_set_at: 1.day.ago)
    Crm::MetaAdsPage.create!(account: other, page_id: '104882', leadgen_receiving: true, leadgen_receiving_since: 1.day.ago)
    before_mark = page.leadgen_receiving_since

    described_class.perform_now

    expect(page.reload.leadgen_receiving_since).to eq(before_mark)
  end
end
