require 'rails_helper'

# Anúncios da Meta › Formulários (#2195, flag `meta_ads_formularios`): sem a flag 404 sem chamar a Meta; ver pede
# meta_ads_view; escolher funil, ligar/parar a Página e trazer os antigos pedem meta_ads_manage; o funil tem de ser um
# que a pessoa enxerga e a etapa tem de ser dele; formulário de Página que o token não alcança é 404.
RSpec.describe 'CRM meta ads lead forms (#2195)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_lead_forms" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:page_token) { 'page-token-de-teste' }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:forms) do
    [
      { id: '9001', name: 'Orçamento de verão', status: 'ACTIVE', leads_count: 37 },
      { id: '9003', name: 'Lista VIP', status: 'ARCHIVED', leads_count: 212 },
      { id: '9009', name: 'Apagado', status: 'DELETED', leads_count: 1 }
    ]
  end

  before do
    account.enable_features!('meta_ads_formularios')
    create_meta_ads_insights_connection(account)
  end

  def stub_pages
    stub_request(:get, meta_graph_url('me/accounts'))
      .with(query: hash_including('fields' => 'id,name,access_token'), headers: { 'Authorization' => "Bearer #{MetaAdsHelpers::TEST_TOKEN}" })
      .to_return(status: 200, headers: json, body: { data: [{ id: '104882', name: 'Studio Aurora', access_token: page_token }] }.to_json)
    stub_request(:get, meta_graph_url('104882/leadgen_forms'))
      .with(query: hash_including('fields' => Meta::AdsGraphClient::LEAD_FORM_FIELDS), headers: { 'Authorization' => "Bearer #{page_token}" })
      .to_return(status: 200, headers: json, body: { data: forms }.to_json)
  end

  def meta_lead(id, name)
    { id: id, created_time: '2026-10-20T12:00:00+0000', form_id: '9001', ad_id: '1', ad_name: 'Carrossel', campaign_name: 'Verão',
      field_data: [{ name: 'full_name', values: [name] }, { name: 'phone_number', values: ["+55119876500#{id[-2..]}"] }] }
  end

  def stub_leads(form_id, leads)
    stub_request(:get, meta_graph_url("#{form_id}/leads"))
      .with(query: hash_including('fields' => Meta::AdsGraphClient::LEAD_FIELDS), headers: { 'Authorization' => "Bearer #{page_token}" })
      .to_return(status: 200, headers: json, body: { data: leads }.to_json)
    stub_request(:get, meta_graph_url(form_id))
      .with(query: { fields: Meta::AdsGraphClient::LEAD_FORM_QUESTION_FIELDS })
      .to_return(status: 200, headers: json, body: { id: form_id, questions: [{ key: 'full_name', label: 'Nome' }] }.to_json)
  end

  # Em segundo plano (contar e trazer os antigos), o token da Página sai do token do cliente.
  def stub_page_token
    stub_request(:get, meta_graph_url('104882')).with(query: { fields: 'access_token' })
                                                .to_return(status: 200, headers: json, body: { id: '104882', access_token: page_token }.to_json)
  end

  # A contagem dos antigos fica guardada no cache (no teste, null_store): aqui um de verdade.
  def with_real_cache
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  # A assinatura da Página é do Crm::MetaAds::PageSubscription (infra, #2200): aqui só o que pedimos a ele.
  def stub_subscription
    subscription = instance_double(Crm::MetaAds::PageSubscription, add!: true, remove!: true)
    allow(Crm::MetaAds::PageSubscription).to receive(:new)
      .with(page_id: '104882', access_token: page_token).and_return(subscription)
    subscription
  end

  def put_destination(pipeline_id: pipeline.id, stage_id: stage.id, import_past: false, user: admin)
    put "#{path}/forms/9001/destination", params: { pipeline_id: pipeline_id, stage_id: stage_id, import_past: import_past },
                                          headers: user.create_new_auth_token, as: :json
  end

  it 'sem a flag responde 404 e não chama a Meta' do
    account.disable_features!('meta_ads_formularios')

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'agente sem meta_ads_view: 403' do
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'lista as Páginas com os formulários ativos e arquivados e os funis; quantos preencheram é contado em segundo plano' do
    with_real_cache
    stub_pages
    stub_page_token
    stub_leads('9001', [meta_lead('L01', 'Ana'), meta_lead('L02', 'Bia')])
    stub_leads('9003', [meta_lead('L03', 'Caio')])
    stage

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    page = response.parsed_body['pages'].sole
    expect(page).to include('id' => '104882', 'name' => 'Studio Aurora', 'receiving' => false)
    expect(page['forms'].map { |form| form.slice('id', 'status', 'past_count', 'destination') }).to eq(
      [{ 'id' => '9001', 'status' => 'ACTIVE', 'past_count' => nil, 'destination' => nil },
       { 'id' => '9003', 'status' => 'ARCHIVED', 'past_count' => nil, 'destination' => nil }]
    )
    expect(a_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))).not_to have_been_made
    expect(response.parsed_body['pipelines'].sole).to include('id' => pipeline.id, 'stages' => [{ 'id' => stage.id, 'name' => stage.name }])
    expect(response.parsed_body['recent_leads']).to eq([])
    expect(response.body).not_to include(page_token)
  end

  it 'quantos preencheram nos últimos 90 dias aparece depois da contagem em segundo plano' do
    with_real_cache
    stub_pages
    stub_page_token
    stub_leads('9001', [meta_lead('L01', 'Ana'), meta_lead('L02', 'Bia')])
    stub_leads('9003', [meta_lead('L03', 'Caio')])

    get path, headers: admin.create_new_auth_token, as: :json
    perform_enqueued_jobs
    get path, headers: admin.create_new_auth_token, as: :json

    counts = response.parsed_body['pages'].sole['forms'].to_h { |form| [form['id'], form['past_count']] }
    expect(counts).to eq('9001' => 2, '9003' => 1)
  end

  it 'abrir a tela de novo enquanto conta não pede outra contagem' do
    with_real_cache
    stub_pages

    2.times { get path, headers: admin.create_new_auth_token, as: :json }

    expect(enqueued_jobs.count { |job| job['job_class'] == 'Crm::MetaAds::LeadForms::CountPastJob' }).to eq(2)
  end

  it 'uma Página que a Meta não deixa ler agora aparece com o motivo e não derruba as outras' do
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                     .to_return(status: 200, headers: json, body: {
                                                       data: [{ id: '104882', name: 'Studio Aurora', access_token: page_token },
                                                              { id: '555', name: 'Outra', access_token: 'outro-token' }]
                                                     }.to_json)
    stub_request(:get, meta_graph_url('104882/leadgen_forms')).with(query: hash_including({}))
                                                              .to_return(status: 500, headers: json, body: '{}')
    stub_request(:get, meta_graph_url('555/leadgen_forms')).with(query: hash_including({}))
                                                           .to_return(status: 200, headers: json, body: { data: forms.first(1) }.to_json)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    pages = response.parsed_body['pages'].index_by { |page| page['id'] }
    expect(pages['104882']).to include('forms' => [], 'error' => 'meta_unavailable')
    expect(pages['555']['forms'].pluck('id')).to eq(['9001'])
  end

  it 'escolher o funil guarda o destino, liga a Página (soma o leadgen) e traz quem já preencheu em segundo plano' do
    stub_pages
    stub_page_token
    subscription = stub_subscription
    stub_leads('9001', [meta_lead('L01', 'Ana'), meta_lead('L02', 'Bia')])

    put_destination(import_past: true)

    expect(subscription).to have_received(:add!).with(%w[leadgen])
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('importing' => true)
    expect(response.parsed_body['destination']).to include('pipeline_id' => pipeline.id, 'stage_id' => stage.id, 'stage_name' => stage.name)
    expect(Crm::MetaAdsPage.find_by(account: account, page_id: '104882')).to have_attributes(leadgen_receiving: true, name: 'Studio Aurora')
    expect(account.crm_cards.count).to eq(0)
    audit = Audited.audit_class.where(auditable: account, action: 'meta_ads_lead_form_destination').last
    expect(audit).to have_attributes(user_id: admin.id)
  end

  it 'o job traz quem já preencheu para a etapa e deixa na Auditoria quantos entraram' do
    stub_pages
    stub_page_token
    stub_subscription
    stub_leads('9001', [meta_lead('L01', 'Ana'), meta_lead('L02', 'Bia')])

    perform_enqueued_jobs { put_destination(import_past: true) }

    expect(account.crm_cards.where(stage: stage).pluck(:title)).to contain_exactly('Ana', 'Bia')
    done = Audited.audit_class.where(auditable: account, action: 'meta_ads_lead_form_past_imported').last
    expect(done).to have_attributes(user_id: admin.id)
    expect(done.audited_changes).to include('imported' => 2, 'truncated' => false, 'brought' => false)
  end

  it 'mais leads do que o teto de segurança da leitura: entra o que coube e a Auditoria diz que cortou' do
    stub_const('Meta::AdsGraphClient::LeadForms::LEADS_MAX_PAGES', 1)
    stub_pages
    stub_page_token
    stub_subscription
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))
                                                    .to_return(status: 200, headers: json, body: {
                                                      data: [meta_lead('L01', 'Ana')],
                                                      paging: { cursors: { after: 'X' }, next: 'https://graph.facebook.com/next' }
                                                    }.to_json)
    stub_request(:get, meta_graph_url('9001')).with(query: { fields: Meta::AdsGraphClient::LEAD_FORM_QUESTION_FIELDS })
                                              .to_return(status: 200, headers: json, body: { id: '9001', questions: [] }.to_json)

    perform_enqueued_jobs { put_destination(import_past: true) }

    done = Audited.audit_class.where(auditable: account, action: 'meta_ads_lead_form_past_imported').last
    expect(done.audited_changes).to include('imported' => 1, 'truncated' => true)
  end

  it 'etapa de outro funil: 422 sem chamar a Meta' do
    other = create_crm_pipeline(account: account, user: admin, name: 'Outro').last

    put_destination(stage_id: other.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'formulário que não é de nenhuma Página do token: 404' do
    stub_pages

    put "#{path}/forms/7777/destination", params: { pipeline_id: pipeline.id, stage_id: stage.id },
                                          headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(Crm::MetaAdsLeadForm.count).to eq(0)
  end

  it 'parar de receber tira só o leadgen, mantém o destino e a Página fica parada' do
    stub_pages
    Crm::MetaAdsPage.create!(account: account, page_id: '104882', leadgen_receiving: true)
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', pipeline: pipeline, stage: stage)
    subscription = stub_subscription
    stub_leads('9003', [])

    delete "#{path}/pages/104882/receive", headers: admin.create_new_auth_token, as: :json

    expect(subscription).to have_received(:remove!).with(%w[leadgen])

    expect(response).to have_http_status(:ok)
    expect(Crm::MetaAdsPage.last.leadgen_receiving).to be(false)
    expect(Crm::MetaAdsLeadForm.last.pipeline_id).to eq(pipeline.id)
    expect(response.parsed_body['pages'].sole['receiving']).to be(false)
  end

  it 'parar numa conta não desassina a Página que outra conta ainda recebe' do
    stub_pages
    other = create(:account)
    Crm::MetaAdsPage.create!(account: other, page_id: '104882', leadgen_receiving: true)
    Crm::MetaAdsPage.create!(account: account, page_id: '104882', leadgen_receiving: true)
    subscription = stub_subscription
    stub_leads('9001', [])
    stub_leads('9003', [])

    delete "#{path}/pages/104882/receive", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(subscription).not_to have_received(:remove!)
    expect(Crm::MetaAdsPage.find_by(account: account).leadgen_receiving).to be(false)
    expect(Crm::MetaAdsPage.find_by(account: other).leadgen_receiving).to be(true)
  end

  it 'a Meta recusa ler os antigos: o destino vale, a Página fica ligada e a Auditoria registra' do
    stub_pages
    stub_page_token
    stub_subscription
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))
                                                    .to_return(status: 400, headers: json, body: meta_graph_error(100).to_json)
    stub_request(:get, meta_graph_url('9001')).with(query: { fields: Meta::AdsGraphClient::LEAD_FORM_QUESTION_FIELDS })
                                              .to_return(status: 200, headers: json, body: { id: '9001', questions: [] }.to_json)

    perform_enqueued_jobs { put_destination(import_past: true) }

    expect(response).to have_http_status(:ok)
    expect(Crm::MetaAdsLeadForm.find_by(form_id: '9001').pipeline_id).to eq(pipeline.id)
    expect(Crm::MetaAdsPage.find_by(account: account).leadgen_receiving).to be(true)
    done = Audited.audit_class.where(auditable: account, action: 'meta_ads_lead_form_past_imported').last
    expect(done.audited_changes).to include('import_error' => 'meta_refused')
  end

  it 'Meta fora do ar: 503 meta_unavailable' do
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({})).to_return(status: 500, body: '{}', headers: json)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq('error' => 'meta_unavailable')
  end

  it 'falha ao contar os antigos de um formulário não derruba a tela: o número vem nil' do
    with_real_cache
    stub_pages
    stub_page_token
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({})).to_return(status: 500, body: '{}', headers: json)
    stub_leads('9003', [meta_lead('L03', 'Caio')])

    get path, headers: admin.create_new_auth_token, as: :json
    perform_enqueued_jobs
    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    counts = response.parsed_body['pages'].sole['forms'].to_h { |form| [form['id'], form['past_count']] }
    expect(counts).to eq('9001' => nil, '9003' => 1)
  end

  it 'Página sem pages_manage_metadata: 422 meta_refused e a Página continua como estava' do
    stub_pages
    refusal = Crm::MetaAds::PageSubscription::Error.new('pages_manage_metadata', code: 200, http_code: 403)
    allow(stub_subscription).to receive(:add!).and_raise(refusal)

    post "#{path}/pages/104882/receive", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'meta_refused')
    expect(Crm::MetaAdsPage.leadgen_receiving).to be_empty
  end

  it 'Meta fora do ar ao ligar a Página: 503 e a Página continua como estava' do
    stub_pages
    unavailable = Crm::MetaAds::PageSubscription::Error.new('timeout', code: nil, http_code: nil)
    allow(stub_subscription).to receive(:add!).and_raise(unavailable)

    post "#{path}/pages/104882/receive", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:service_unavailable)
    expect(Crm::MetaAdsPage.leadgen_receiving).to be_empty
  end

  it 'formulário arquivado: traz quem preencheu em segundo plano, sem guardar destino nem ligar a Página' do
    stub_pages
    stub_page_token
    stub_subscription
    stub_leads('9003', [meta_lead('L03', 'Caio')])

    post "#{path}/forms/9003/bring_past", params: { pipeline_id: pipeline.id, stage_id: stage.id },
                                          headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('importing' => true, 'pipeline_name' => pipeline.name, 'stage_name' => stage.name)

    perform_enqueued_jobs

    expect(Crm::MetaAdsLeadForm.find_by(form_id: '9003')).to have_attributes(pipeline_id: nil, brought_count: 1)
    expect(account.crm_cards.pluck(:title)).to eq(['Caio'])
    expect(Crm::MetaAds::PageSubscription).not_to have_received(:new)
  end

  it 'tirar o destino apaga o funil do formulário' do
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', pipeline: pipeline, stage: stage)

    delete "#{path}/forms/9001/destination", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(Crm::MetaAdsLeadForm.last).to have_attributes(pipeline_id: nil, stage_id: nil)
  end

  context 'when the form destination is a funnel the user cannot see' do
    let(:hidden) { create_crm_pipeline(account: account, user: admin, name: 'Diretoria') }

    before do
      Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', pipeline: hidden.first, stage: hidden.last)
      hidden_id = hidden.first.id
      allow_any_instance_of(Crm::Access::VisiblePipelines).to( # rubocop:disable RSpec/AnyInstance
        receive(:apply).and_wrap_original { |original, scope| original.call(scope).where.not(id: hidden_id) }
      )
    end

    it 'não troca o destino: 403 sem chamar a Meta' do
      put_destination

      expect(response).to have_http_status(:forbidden)
      expect(Crm::MetaAdsLeadForm.last.pipeline_id).to eq(hidden.first.id)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'não tira o destino: 403' do
      delete "#{path}/forms/9001/destination", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Crm::MetaAdsLeadForm.last.pipeline_id).to eq(hidden.first.id)
    end

    it 'a tela não mostra o nome do funil nem da etapa' do
      stub_pages
      stub_leads('9003', [])

      get path, headers: admin.create_new_auth_token, as: :json

      destination = response.parsed_body['pages'].sole['forms'].find { |form| form['id'] == '9001' }['destination']
      expect(destination).to include('pipeline_id' => hidden.first.id, 'pipeline_name' => nil, 'stage_name' => nil)
      expect(response.body).not_to include('Diretoria')
    end
  end

  it 'destino num funil arquivado que a pessoa enxerga: dá para tirar' do
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', pipeline: pipeline, stage: stage)
    pipeline.update!(status: :archived)

    delete "#{path}/forms/9001/destination", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
  end

  it 'a Meta recusa ligar a Página ao escolher o funil: 422 e o formulário continua como estava' do
    stub_pages
    refusal = Crm::MetaAds::PageSubscription::Error.new('pages_manage_metadata', code: 200, http_code: 403)
    allow(stub_subscription).to receive(:add!).and_raise(refusal)

    put_destination

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Crm::MetaAdsLeadForm.find_by(form_id: '9001')&.destination?).to be_falsey
  end

  it 'escolher o funil grava o destino antes de ligar a Página: lead que chega no meio já tem para onde ir' do
    stub_pages
    subscription = stub_subscription
    destination_when_subscribed = nil
    allow(subscription).to receive(:add!) do
      destination_when_subscribed = Crm::MetaAdsLeadForm.find_by(form_id: '9001')&.destination?
    end

    put_destination

    expect(response).to have_http_status(:ok)
    expect(destination_when_subscribed).to be(true)
  end

  it 'parar uma Página que saiu do token: esta conta para, sem chamar a assinatura' do
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                     .to_return(status: 200, headers: json, body: { data: [] }.to_json)
    Crm::MetaAdsPage.create!(account: account, page_id: '104882', leadgen_receiving: true)
    allow(Crm::MetaAds::PageSubscription).to receive(:new)

    delete "#{path}/pages/104882/receive", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(Crm::MetaAdsPage.find_by(account: account).leadgen_receiving).to be(false)
    expect(Crm::MetaAds::PageSubscription).not_to have_received(:new)
  end

  it 'outra conta com a mesma Página não vê nem mexe nos formulários e leads desta' do
    stub_pages
    stub_leads('9001', [])
    stub_leads('9003', [])
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', pipeline: pipeline, stage: stage)
    Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: pipeline, stage: stage, form_name: 'Orçamento')
                                     .import(meta_lead('L01', 'Ana').deep_stringify_keys)
    other, other_admin = create_account_and_user
    other.enable_features!('meta_ads_formularios')
    create_meta_ads_insights_connection(other)
    other_path = "/api/v1/accounts/#{other.id}/crm/meta_ads_lead_forms"

    get other_path, headers: other_admin.create_new_auth_token, as: :json

    forms = response.parsed_body['pages'].sole['forms']
    expect(forms.pluck('destination').compact).to be_empty
    expect(response.parsed_body['recent_leads']).to eq([])
    expect(response.body).not_to include('Ana')

    delete "#{other_path}/forms/9001/destination", headers: other_admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(Crm::MetaAdsLeadForm.find_by(account: account, form_id: '9001').pipeline_id).to eq(pipeline.id)
  end

  it 'quem chegou num card que a pessoa não enxerga não aparece na lista' do
    stub_pages
    stub_leads('9001', [])
    stub_leads('9003', [])
    Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: pipeline, stage: stage, form_name: 'Orçamento')
                                     .import(meta_lead('L01', 'Ana').deep_stringify_keys)
    allow_any_instance_of(Crm::Access::CardScope).to receive(:apply) { |_scope, cards| cards.none } # rubocop:disable RSpec/AnyInstance

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['recent_leads']).to eq([])
  end

  it 'mostra quem chegou pelos formulários, com o card e o funil' do
    stub_pages
    stub_leads('9001', [])
    stub_leads('9003', [])
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento de verão',
                                 pipeline: pipeline, stage: stage)
    Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: pipeline, stage: stage, form_name: 'Orçamento de verão')
                                     .import(meta_lead('L01', 'Ana').deep_stringify_keys)

    get path, headers: admin.create_new_auth_token, as: :json

    lead = response.parsed_body['recent_leads'].sole
    expect(lead).to include('name' => 'Ana', 'phone' => '+5511987650001', 'form_name' => 'Orçamento de verão', 'ad_name' => 'Carrossel',
                            'pipeline_id' => pipeline.id, 'stage_name' => stage.name, 'new_contact' => true)
    expect(lead['card_id']).to eq(account.crm_cards.last.id)
  end
end
