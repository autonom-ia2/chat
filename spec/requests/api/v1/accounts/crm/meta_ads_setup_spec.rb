require 'rails_helper'

# Conexão guiada de Anúncios da Meta (#1047): contas e Pixels em lista, escolha só depois de ler de verdade,
# trava entre clientes no modo parceiro, destinos e "avisar a Meta quando vender".
RSpec.describe 'CRM meta_ads_connection setup API', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:platform_token) { 'EAAGplataformatoken1234567890SEGREDO' }
  let(:portfolio) { '1013433763956648' }
  let(:partner_business) { '555000111222333' }
  let(:system_user) { '61589197595551' }
  let(:ad_account) { '2196424464528988' }
  let(:pixel) { '2164882667623689' }

  before { enable_test_encryption! }

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def account_row(id, owner:, name: 'CA - Placement Seguros')
    { id: "act_#{id}", account_id: id, name: name, account_status: 1, currency: 'BRL', business: { id: owner, name: 'Dono' } }
  end

  def with_whatsapp_portfolio(target = account, id = portfolio)
    channel = create(:channel_whatsapp, account: target, sync_templates: false, validate_provider_config: false)
    create(:inbox, account: target, channel: channel)
    channel.update_columns(phone_number_health: { 'business_portfolio_id' => id }) # rubocop:disable Rails/SkipsModelValidations
  end

  def configure_platform
    AiProviderCredential.create!(provider: 'meta_ads', api_key: platform_token)
    InstallationConfig.where(name: 'META_ADS_PARTNER_BUSINESS_ID').first_or_create(value: partner_business).update!(value: partner_business)
    InstallationConfig.where(name: 'META_ADS_SYSTEM_USER_ID').first_or_create(value: system_user).update!(value: system_user)
    GlobalConfig.clear_cache('META_ADS_PARTNER_BUSINESS_ID', 'META_ADS_SYSTEM_USER_ID')
  end

  def stub_graph(path, body, token: platform_token, query: hash_including({}), status: 200)
    stub_request(:get, meta_graph_url(path)).with(query: query, headers: { 'Authorization' => "Bearer #{token}" })
                                            .to_return(json(body).merge(status: status))
  end

  def stub_partner_listing(rows, assigned: [])
    stub_graph("#{partner_business}/client_ad_accounts", { data: rows })
    stub_graph('me/adaccounts', { data: assigned })
  end

  def stub_reads(id = ad_account, owner: portfolio, token: platform_token, spend: '1720.40')
    stub_graph("act_#{id}", account_row(id, owner: owner), token: token)
    stub_graph("act_#{id}/insights", { data: [{ spend: spend }] }, token: token)
    stub_graph("act_#{id}/adspixels", { data: [{ id: pixel, name: 'Pixel Placement Seguros', last_fired_time: '2026-10-06T10:00:00+0000' }] },
               token: token)
  end

  describe 'GET ad_accounts (parceiro)' do
    before do
      configure_platform
      with_whatsapp_portfolio
    end

    it 'recusa da Meta ao conferir o acesso vira erro na tela, nunca conta "ainda liberando", e vai para o log sem token' do
      stub_graph("#{partner_business}/client_ad_accounts", { data: [account_row(ad_account, owner: portfolio)] })
      stub_graph('me/adaccounts', { error: { code: 200, message: 'Permissions error' } }, status: 403)
      logged = []
      allow(Rails.logger).to receive(:warn) { |line| logged << line }

      get "#{base}/ad_accounts", params: { mode: 'partner' }, headers: auth_headers(admin)

      expect(response.parsed_body['error']).to eq('no_access')
      line = logged.find { |text| text.start_with?('[MetaAdsGraph]') }
      expect(line).to include('GET me/adaccounts', 'code=200', 'Permissions error')
      expect(line).not_to include(platform_token)
    end

    it 'lista só contas do portfólio do WhatsApp desta conta, a com mais gasto recomendada' do
      stub_partner_listing([account_row(ad_account, owner: portfolio), account_row('999', owner: '777', name: 'De outro cliente')],
                           assigned: [account_row(ad_account, owner: portfolio)])
      stub_reads

      get "#{base}/ad_accounts", params: { mode: 'partner' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body['ad_accounts']
      expect(rows.pluck('id')).to eq([ad_account])
      expect(rows.first).to include('name' => 'CA - Placement Seguros', 'ready' => true, 'recommended' => true, 'spend_30d' => 1720.4)
      expect(response.body).not_to include(platform_token)
    end

    it 'listar não muda nada na Meta: conta compartilhada e ainda não atribuída aparece aguardando' do
      stub_partner_listing([account_row(ad_account, owner: portfolio)])
      assign = stub_request(:post, meta_graph_url("act_#{ad_account}/assigned_users"))

      get "#{base}/ad_accounts", params: { mode: 'partner' }, headers: auth_headers(admin)

      expect(assign).not_to have_been_requested
      expect(response.parsed_body['ad_accounts'].first).to include('ready' => false, 'recommended' => false, 'spend_30d' => nil)
    end

    it 'ignora portfólio que aparece no WhatsApp de mais de uma conta (revendedor)' do
      with_whatsapp_portfolio(create(:account))
      stub_partner_listing([account_row(ad_account, owner: portfolio)], assigned: [account_row(ad_account, owner: portfolio)])

      get "#{base}/ad_accounts", params: { mode: 'partner' }, headers: auth_headers(admin)

      expect(response.parsed_body['error']).to eq('no_portfolio')
    end

    it 'esconde conta já usada por outra conta do Chat2You' do
      other = create(:account)
      Crm::MetaAdsConnection.create!(account: other, mode: 'partner', ad_account_id: ad_account)
      stub_partner_listing([account_row(ad_account, owner: portfolio)], assigned: [account_row(ad_account, owner: portfolio)])

      get "#{base}/ad_accounts", params: { mode: 'partner' }, headers: auth_headers(admin)

      expect(response.parsed_body['ad_accounts']).to eq([])
    end

    it 'sem WhatsApp com portfólio conhecido responde no_portfolio' do
      Channel::Whatsapp.update_all(phone_number_health: {}) # rubocop:disable Rails/SkipsModelValidations

      get "#{base}/ad_accounts", params: { mode: 'partner' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('no_portfolio')
    end
  end

  it 'sem plataforma configurada o modo parceiro responde platform_unavailable' do
    with_whatsapp_portfolio

    get "#{base}/ad_accounts", params: { mode: 'partner' }, headers: auth_headers(admin)

    expect(response.parsed_body['error']).to eq('platform_unavailable')
  end

  it 'modo inválido responde invalid_mode' do
    get "#{base}/ad_accounts", params: { mode: 'qualquer' }, headers: auth_headers(admin)

    expect(response.parsed_body['error']).to eq('invalid_mode')
  end

  it 'modo token lista as contas que o token colado enxerga' do
    create_meta_ads_connection(account)
    stub_graph('me/adaccounts', { data: [account_row(ad_account, owner: '1')] }, token: MetaAdsHelpers::TEST_TOKEN)
    stub_graph("act_#{ad_account}/insights", { data: [{ spend: '10' }] }, token: MetaAdsHelpers::TEST_TOKEN)

    get "#{base}/ad_accounts", params: { mode: 'token' }, headers: auth_headers(admin)

    expect(response.parsed_body['ad_accounts'].first).to include('id' => ad_account, 'ready' => true, 'spend_30d' => 10.0)
  end

  describe 'POST selection' do
    before do
      configure_platform
      with_whatsapp_portfolio
      stub_partner_listing([account_row(ad_account, owner: portfolio)], assigned: [account_row(ad_account, owner: portfolio)])
    end

    it 'atribui o usuário do sistema na escolha quando a conta ainda não estava atribuída' do
      stub_partner_listing([account_row(ad_account, owner: portfolio)])
      assign = stub_request(:post, meta_graph_url("act_#{ad_account}/assigned_users")).to_return(json({ success: true }))
      stub_reads

      post "#{base}/selection", params: { mode: 'partner', ad_account_id: ad_account }, headers: auth_headers(admin), as: :json

      expect(assign).to have_been_requested.once
      expect(response.parsed_body).to include('mode' => 'partner')
    end

    it 'responde platform_access_pending quando a Meta recusa a atribuição, sem gravar' do
      stub_partner_listing([account_row(ad_account, owner: portfolio)])
      stub_request(:post, meta_graph_url("act_#{ad_account}/assigned_users"))
        .to_return(json({ error: { code: 200, message: 'Permissions error' } }).merge(status: 400))

      post "#{base}/selection", params: { mode: 'partner', ad_account_id: ad_account }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('platform_access_pending')
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).to be_empty
    end

    it 'recusa conta que não foi compartilhada por um portfólio desta conta, sem ler a conta' do
      stub_partner_listing([account_row(ad_account, owner: '777')])
      reads = stub_graph("act_#{ad_account}", account_row(ad_account, owner: portfolio))

      post "#{base}/selection", params: { mode: 'partner', ad_account_id: ad_account }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('not_shared')
      expect(reads).not_to have_been_requested
    end

    it 'lê conta, gasto e Pixel antes de gravar e só então fica conectada' do
      stub_reads

      post "#{base}/selection", params: { mode: 'partner', ad_account_id: ad_account, pixel_id: pixel }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('mode' => 'partner', 'status' => 'active')
      expect(response.parsed_body['ad_account']).to eq('id' => ad_account, 'name' => 'CA - Placement Seguros')
      expect(response.parsed_body['pixel']).to eq('id' => pixel, 'name' => 'Pixel Placement Seguros')
      expect(response.parsed_body['verified_at']).to be_present
      connection = Crm::MetaAdsConnection.find_by!(account_id: account.id)
      expect(connection.access_token).to be_nil
      expect(connection.read_token).to eq(platform_token)
    end

    it 'recusa conta de anúncios de outro portfólio' do
      stub_reads(owner: '777')

      post "#{base}/selection", params: { mode: 'partner', ad_account_id: ad_account }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('not_your_portfolio')
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).to be_empty
    end

    it 'não grava quando a Meta não deixa ler o gasto' do
      stub_graph("act_#{ad_account}", account_row(ad_account, owner: portfolio))
      stub_graph("act_#{ad_account}/insights", { error: { code: 200, message: 'no access' } }, status: 403)

      post "#{base}/selection", params: { mode: 'partner', ad_account_id: ad_account }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('no_access')
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).to be_empty
    end

    it 'recusa Pixel que não é da conta' do
      stub_reads

      post "#{base}/selection", params: { mode: 'partner', ad_account_id: ad_account, pixel_id: '123456' }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('pixel_not_found')
    end

    it 'recusa ID que não é de conta de anúncios sem chamar a Meta' do
      post "#{base}/selection", params: { mode: 'partner', ad_account_id: 'act_abc' }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('invalid_ad_account')
    end
  end

  describe 'destinos' do
    let!(:connection) { Crm::MetaAdsConnection.create!(account: account, mode: 'partner', ad_account_id: ad_account, pixel_id: pixel) }

    it 'grava WhatsApp e site como booleanos' do
      patch "#{base}/destinations", params: { destinations: { whatsapp: true, site: 'false', outro: true } }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['destinations']).to eq('whatsapp' => true, 'site' => false)
      expect(connection.reload.destinations).to eq('whatsapp' => true, 'site' => false)
    end
  end

  describe 'avisar a Meta sobre o funil (passo 4)' do
    let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
    let!(:pipeline) { create_crm_pipeline(account: account, user: admin, name: 'Viagem').first }
    let!(:proposal) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta') }

    before do
      Crm::MetaAdsConnection.create!(account: account, mode: 'partner', ad_account_id: ad_account, pixel_id: pixel)
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: whatsapp_inbox)
      create_crm_pipeline(account: account, user: admin, name: 'Sem WhatsApp')
    end

    def new_stage
      pipeline.stages.find_by!(position: 0)
    end

    def save_funnel(params, user = admin)
      patch "#{base}/funnel", params: params, headers: auth_headers(user), as: :json
    end

    it 'lista só funis ligados ao WhatsApp oficial e o que falta em cada um' do
      get "#{base}/funnels", headers: auth_headers(admin), as: :json

      funnels = response.parsed_body['funnels']
      expect(funnels.pluck('name')).to eq(['Viagem'])
      expect(funnels.first['missing']).to eq(%w[sending_off sales_off moves_off stages])
      expect(funnels.first['numbers'].pluck('inbox_id')).to eq([whatsapp_inbox.id])
      expect(response.parsed_body['unlinked_numbers']).to eq([])
    end

    it 'grava os tipos das etapas e liga venda e mudança de etapa, sem trocar perda, dataset nem outro Pixel' do
      meta_sync = { 'events' => { 'lost' => true }, 'dataset_id' => '42', 'pixel_id' => '99' }
      pipeline.update!(metadata: { 'ai' => { 'x' => 1 }, 'meta_sync' => meta_sync })
      new_stage.update!(metadata: { 'funnel_stage_type' => 'qualified', 'ai_criteria' => 'x' })

      stages = [{ id: new_stage.id, funnel_stage_type: 'lead' }, { id: proposal.id, funnel_stage_type: 'opportunity' }]
      save_funnel({ pipeline_id: pipeline.id, stages: stages })

      expect(response).to have_http_status(:ok)
      meta_sync = pipeline.reload.metadata['meta_sync']
      expect(meta_sync).to include('enabled' => true, 'dataset_id' => '42', 'pixel_id' => '99')
      expect(meta_sync['events']).to eq('lost' => true, 'won' => true, 'moved' => true)
      expect(pipeline.metadata['ai']).to eq('x' => 1)
      expect(new_stage.reload.metadata).to eq('funnel_stage_type' => 'lead', 'ai_criteria' => 'x')
      expect(proposal.reload.metadata['funnel_stage_type']).to eq('opportunity')
      expect(response.parsed_body['funnels'].first['missing']).to eq([])
    end

    it 'usa o Pixel da conexão só no funil que não tem um, e "none" limpa o tipo da etapa' do
      proposal.update!(metadata: { 'funnel_stage_type' => 'negotiation' })

      save_funnel({ pipeline_id: pipeline.id, stages: [{ id: proposal.id, funnel_stage_type: 'none' }] })

      expect(pipeline.reload.metadata.dig('meta_sync', 'pixel_id')).to eq(pixel)
      expect(proposal.reload.metadata).not_to have_key('funnel_stage_type')
    end

    it 'para de avisar só este funil e guarda as escolhas' do
      pipeline.update!(metadata: { 'meta_sync' => { 'enabled' => true, 'events' => { 'won' => true, 'moved' => true } } })

      save_funnel({ pipeline_id: pipeline.id, enabled: false })

      expect(pipeline.reload.metadata['meta_sync']).to eq('enabled' => false, 'events' => { 'won' => true, 'moved' => true })
    end

    it 'recusa funil sem WhatsApp oficial, etapa de outro funil e tipo desconhecido' do
      other_pipeline = account.crm_pipelines.find_by!(name: 'Sem WhatsApp')
      foreign = create_crm_stage(account: account, pipeline: other_pipeline, name: 'Outra')

      save_funnel({ pipeline_id: other_pipeline.id, stages: [] })
      expect(response.parsed_body['error']).to eq('funnel_not_found')

      save_funnel({ pipeline_id: pipeline.id, stages: [{ id: foreign.id, funnel_stage_type: 'lead' }] })
      expect(response.parsed_body['error']).to eq('invalid_stage')

      save_funnel({ pipeline_id: pipeline.id, stages: [{ id: proposal.id, funnel_stage_type: 'Purchase' }] })
      expect(response.parsed_body['error']).to eq('invalid_stage_type')
      expect(pipeline.reload.metadata['meta_sync']).to be_nil
      expect(foreign.reload.metadata).to eq({})
    end

    it 'mostra o número que não está em nenhum funil' do
      account.crm_pipeline_inboxes.where(pipeline: pipeline).destroy_all

      get "#{base}/funnels", headers: auth_headers(admin), as: :json

      expect(response.parsed_body['funnels']).to eq([])
      expect(response.parsed_body['unlinked_numbers'].pluck('inbox_id')).to eq([whatsapp_inbox.id])
    end

    it 'sugestão por IA: pede em segundo plano e devolve o endereço para acompanhar' do
      with_modified_env CRM_AI_ENABLED: 'true' do
        expect do
          post "#{base}/suggest_stages", params: { pipeline_id: pipeline.id }, headers: auth_headers(admin), as: :json
        end.to have_enqueued_job(Crm::Ai::InteractiveJob)

        expect(response).to have_http_status(:accepted)
        expect(response.parsed_body['poll_url']).to include('/ai_requests/')
      end
    end

    it 'agente não lê nem grava (403)' do
      get "#{base}/funnels", headers: auth_headers(agent), as: :json
      expect(response).to have_http_status(:forbidden)

      save_funnel({ pipeline_id: pipeline.id, stages: [] }, agent)
      expect(response).to have_http_status(:forbidden)
      expect(pipeline.reload.metadata['meta_sync']).to be_nil
    end
  end

  it 'GET mostra o parceiro sem o token da plataforma' do
    configure_platform

    get base, headers: auth_headers(admin), as: :json

    expect(response.parsed_body['partner']).to eq('available' => true, 'business_id' => partner_business, 'business_name' => 'Hub2You')
    expect(response.body).not_to include(platform_token)
  end
end
