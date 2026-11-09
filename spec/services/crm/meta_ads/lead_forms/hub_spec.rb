require 'rails_helper'

# Marcos de início da reconciliação (#2285): destination_set_at nasce quando o formulário passa a ter destino e some
# quando o destino sai; leadgen_receiving_since nasce quando a Página passa a receber e some quando ela para. Salvar de
# novo não encurta a releitura.
RSpec.describe Crm::MetaAds::LeadForms::Hub do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:page_token) { 'page-token-de-teste' }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:hub) { described_class.new(connection: connection, account: account, remember_pages: true, user: admin) }
  let(:subscription) { instance_double(Crm::MetaAds::PageSubscription, add!: true, remove!: true) }

  before do
    pages = { data: [{ id: '104882', name: 'Studio Aurora', access_token: page_token }] }
    forms = { data: [{ id: '9001', name: 'Orçamento', status: 'ACTIVE' }] }
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                     .to_return(status: 200, headers: json, body: pages.to_json)
    stub_request(:get, meta_graph_url('104882/leadgen_forms')).with(query: hash_including({}))
                                                              .to_return(status: 200, headers: json, body: forms.to_json)
    allow(Crm::MetaAds::PageSubscription).to receive(:new).and_return(subscription)
  end

  def form
    Crm::MetaAdsLeadForm.find_by(account: account, form_id: '9001')
  end

  def page
    Crm::MetaAdsPage.find_by(account: account, page_id: '104882')
  end

  def save!
    hub.save_destination!('9001', pipeline: pipeline, stage: stage, import_past: false)
  end

  it 'salvar o destino carimba o formulário e a Página com a hora em que passaram a valer' do
    freeze_time do
      save!

      expect(form.destination_set_at).to eq(Time.current)
      expect(page.leadgen_receiving_since).to eq(Time.current)
    end
  end

  it 'salvar de novo (mesmo ou outro funil) não move os marcos: a releitura não encurta' do
    save!
    first_form = form.destination_set_at
    first_page = page.leadgen_receiving_since
    other_pipeline, other_stage = create_crm_pipeline(account: account, user: admin, name: 'Outro')

    travel 2.hours do
      hub.save_destination!('9001', pipeline: other_pipeline, stage: other_stage, import_past: false)
    end

    expect(form.pipeline_id).to eq(other_pipeline.id)
    expect(form.destination_set_at).to eq(first_form)
    expect(page.leadgen_receiving_since).to eq(first_page)
  end

  it 'destino que estava num funil arquivado: salvar de novo começa o marco dali (o webhook não mandava ninguém)' do
    save!
    pipeline.update!(status: :archived)
    other_pipeline, other_stage = create_crm_pipeline(account: account, user: admin, name: 'Outro')

    travel 2.hours do
      hub.save_destination!('9001', pipeline: other_pipeline, stage: other_stage, import_past: false)
      expect(form.destination_set_at).to be_within(1.second).of(Time.current)
    end
  end

  it 'linha de antes do #2285 (marcos nulos) ganha os marcos quando o destino é salvo de novo' do
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', pipeline: pipeline, stage: stage)
    Crm::MetaAdsPage.create!(account: account, page_id: '104882', leadgen_receiving: true)

    freeze_time do
      save!

      expect(form.destination_set_at).to eq(Time.current)
      expect(page.leadgen_receiving_since).to eq(Time.current)
    end
  end

  it 'tirar o destino apaga o marco; salvar depois começa de novo dali' do
    save!
    hub.remove_destination!('9001')
    expect(form.destination_set_at).to be_nil

    travel 3.hours do
      save!
      expect(form.destination_set_at).to be_within(1.second).of(Time.current)
    end
  end

  it 'parar a Página apaga o marco dela; religar começa de novo dali' do
    save!
    hub.stop!('104882')
    expect(page).to have_attributes(leadgen_receiving: false, leadgen_receiving_since: nil)

    travel 3.hours do
      hub.receive!('104882')
      expect(page.leadgen_receiving_since).to be_within(1.second).of(Time.current)
    end
  end

  it 'parar uma Página que saiu do token também apaga o marco' do
    Crm::MetaAdsPage.create!(account: account, page_id: '555', leadgen_receiving: true, leadgen_receiving_since: 1.day.ago)

    hub.stop!('555')

    expect(Crm::MetaAdsPage.find_by(account: account, page_id: '555'))
      .to have_attributes(leadgen_receiving: false, leadgen_receiving_since: nil)
  end

  it 'a Meta recusa ligar a Página: o formulário volta ao destino e ao marco que tinha' do
    allow(subscription).to receive(:add!).and_raise(Crm::MetaAds::PageSubscription::Error.new('no', code: 200, http_code: 403))

    expect { save! }.to raise_error(Crm::MetaAds::LeadForms::Error)

    expect(form).to have_attributes(pipeline_id: nil, stage_id: nil, destination_set_at: nil)
  end
end
