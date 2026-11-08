require 'rails_helper'

# Lead que chega pelo webhook da Página (#2195, contrato com o #2200): acha as contas em que a Página está recebendo e o
# formulário tem funil, busca o lead com o token da Página (leads_retrieval) e cria o card. Sem flag, Página parada ou
# formulário sem destino: nada é chamado. Repetido: um card só.
RSpec.describe Webhooks::FacebookLeadgenJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:page_token) { 'page-token-de-teste' }
  let(:value) { { 'leadgen_id' => 'L77', 'form_id' => '9001', 'page_id' => '104882', 'ad_id' => '1', 'created_time' => 1_761_566_400 } }

  before do
    account.enable_features!('meta_ads_formularios')
    create_meta_ads_insights_connection(account)
    Crm::MetaAdsPage.create!(account: account, page_id: '104882', leadgen_receiving: true)
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento',
                                 pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last)
  end

  def stub_meta(status: 200)
    stub_request(:get, meta_graph_url('104882')).with(query: { fields: 'access_token' })
                                                .to_return(status: 200, headers: json, body: { access_token: page_token, id: '104882' }.to_json)
    stub_request(:get, meta_graph_url('9001')).with(query: { fields: Meta::AdsGraphClient::LEAD_FORM_QUESTION_FIELDS })
                                              .to_return(status: 200, headers: json, body: { id: '9001', questions: [] }.to_json)
    body = if status == 200
             { id: 'L77', created_time: '2026-10-27T12:00:00+0000', form_id: '9001', ad_name: 'Carrossel',
               field_data: [{ name: 'full_name', values: ['Rafael Costa'] }] }
           else
             meta_graph_error(1)
           end
    stub_request(:get, meta_graph_url('L77')).with(query: { fields: Meta::AdsGraphClient::LEAD_FIELDS },
                                                   headers: { 'Authorization' => "Bearer #{page_token}" })
                                             .to_return(status: status, headers: json, body: body.to_json)
  end

  it 'cria o card do lead na etapa do formulário' do
    stub_meta

    described_class.perform_now('104882', value, 1_761_566_400)

    expect(account.crm_cards.sole).to have_attributes(title: 'Rafael Costa', stage_id: pipeline_and_stage.last.id)
  end

  it 'o mesmo lead duas vezes: um card só' do
    stub_meta

    2.times { described_class.perform_now('104882', value, 1_761_566_400) }

    expect(account.crm_cards.count).to eq(1)
  end

  it 'Página parada: não chama a Meta' do
    Crm::MetaAdsPage.update_all(leadgen_receiving: false) # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now('104882', value, nil)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'sem a flag: não chama a Meta' do
    account.disable_features!('meta_ads_formularios')

    described_class.perform_now('104882', value, nil)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'formulário sem funil escolhido: não chama a Meta' do
    Crm::MetaAdsLeadForm.update_all(pipeline_id: nil, stage_id: nil) # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now('104882', value.merge('form_id' => '9001'), nil)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'Página em duas contas, a Meta fora do ar na primeira: a segunda recebe e o job tenta de novo no fim' do
    other = create(:account)
    other.enable_features!('meta_ads_formularios')
    other_connection = create_meta_ads_insights_connection(other)
    Crm::MetaAdsPage.create!(account: other, page_id: '104882', leadgen_receiving: true)
    other_admin = create(:user, account: other, role: :administrator)
    other_pipeline, other_stage = create_crm_pipeline(account: other, user: other_admin)
    Crm::MetaAdsLeadForm.create!(account: other, page_id: '104882', form_id: '9001', pipeline: other_pipeline, stage: other_stage)
    stub_meta
    first_account = Crm::MetaAdsPage.leadgen_receiving.where(page_id: '104882').order(:id).first.account_id
    allow(Crm::MetaAdsConnection).to receive(:active).and_wrap_original do |original|
      relation = original.call
      allow(relation).to receive(:find_by).and_wrap_original do |find, **args|
        raise Crm::MetaAds::LeadForms::Unavailable if args[:account_id] == first_account

        find.call(**args)
      end
      relation
    end

    expect { described_class.new.perform('104882', value, nil) }.to raise_error(Crm::MetaAds::LeadForms::Unavailable)
    expect(Crm::Card.where(account_id: first_account).count).to eq(0)
    expect(Crm::Card.where(account_id: [account.id, other.id] - [first_account]).count).to eq(1)
    expect(other_connection).to be_persisted
  end

  it 'funil arquivado: não recebe gente nova e não chama a Meta' do
    pipeline_and_stage.first.update!(status: :archived)

    described_class.perform_now('104882', value, nil)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(account.crm_cards.count).to eq(0)
  end

  it 'token do cliente recusado (190): a conexão fica precisando de atenção e nada é criado' do
    stub_request(:get, meta_graph_url('104882')).with(query: { fields: 'access_token' })
                                                .to_return(status: 400, headers: json, body: meta_graph_error(190).to_json)

    described_class.perform_now('104882', value, nil)

    expect(Crm::MetaAdsConnection.find_by(account_id: account.id).status).to eq('invalid')
    expect(account.crm_cards.count).to eq(0)
  end

  it 'sem permissão de ler o lead: vai ao rastreador só com o código, sem token' do
    stub_meta
    stub_request(:get, meta_graph_url('L77')).with(query: { fields: Meta::AdsGraphClient::LEAD_FIELDS })
                                             .to_return(status: 403, headers: json, body: meta_graph_error(200).to_json)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now('104882', value, nil)

    expect(ChatwootExceptionTracker).to have_received(:new) do |error, **|
      expect(error.message).to include('200')
      expect(error.message).not_to include(page_token)
    end
    expect(account.crm_cards.count).to eq(0)
  end

  it 'conexão no modo parceira (token da plataforma): não chama a Meta' do
    Crm::MetaAdsConnection.find_by(account_id: account.id).update_columns(mode: 'partner') # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now('104882', value, nil)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'formulário que esta conta não configurou: não chama a Meta' do
    described_class.perform_now('104882', value.merge('form_id' => '5555'), nil)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(account.crm_cards.count).to eq(0)
  end

  it 'Meta fora do ar nas 5 tentativas: o leadgen_id vai ao rastreador para "Trazer quem preencheu" recuperar' do
    stub_meta(status: 500)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    perform_enqueued_jobs { described_class.perform_later('104882', value, nil) }

    expect(ChatwootExceptionTracker).to have_received(:new).with(having_attributes(message: include('leadgen_id=L77')))
    expect(account.crm_cards.count).to eq(0)
  end

  it 'falha passageira da Meta: levanta para o job tentar de novo' do
    stub_meta(status: 500)

    expect { described_class.new.perform('104882', value, nil) }.to raise_error(Crm::MetaAds::LeadForms::Unavailable)
    expect(account.crm_cards.count).to eq(0)
  end
end
