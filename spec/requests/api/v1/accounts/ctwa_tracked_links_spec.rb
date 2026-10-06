require 'rails_helper'

RSpec.describe 'CTWA tracked links API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+15551234567', provider: 'whatsapp_cloud', validate_provider_config: false,
                              sync_templates: false)
  end
  let(:inbox) { channel.inbox }

  it 'requires authentication' do
    get "/api/v1/accounts/#{account.id}/ctwa_tracked_links"

    expect(response).to have_http_status(:unauthorized)
  end

  it 'creates a tracked link and returns the public payload' do
    with_modified_env FRONTEND_URL: 'https://app.example.com' do
      post "/api/v1/accounts/#{account.id}/ctwa_tracked_links",
           params: { name: 'Flyer Julho', inbox_id: inbox.id, prefilled_text: 'Quero atendimento' },
           headers: auth_headers(admin)
    end

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    tracked_link = Ctwa::TrackedLink.find(payload['id'])

    expect(payload).to include(
      'name' => 'Flyer Julho',
      'code' => tracked_link.code,
      'prefilled_text' => 'Quero atendimento',
      'clicks_count' => 0,
      'conversations_count' => 0,
      'inbox_id' => inbox.id,
      'wa_link' => tracked_link.wa_link,
      'short_url' => "https://app.example.com/l/#{tracked_link.code}"
    )
  end

  it 'lists tracked links for the current account only' do
    own_link = Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'Meu link', code: 'ABC234')
    other_account = create(:account)
    other_channel = create(:channel_whatsapp, account: other_account, phone_number: '+15557654321', provider: 'whatsapp_cloud',
                                              validate_provider_config: false, sync_templates: false)
    Ctwa::TrackedLink.create!(account: other_account, inbox: other_channel.inbox, name: 'Outro link', code: 'XYZ789')

    with_modified_env FRONTEND_URL: 'https://app.example.com' do
      get "/api/v1/accounts/#{account.id}/ctwa_tracked_links", headers: auth_headers(admin)
    end

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload.pluck('id')).to eq([own_link.id])
    expect(payload.first['short_url']).to eq('https://app.example.com/l/ABC234')
  end

  it 'rejects a non-WhatsApp inbox with 422' do
    api_inbox = create(:inbox, account: account)

    post "/api/v1/accounts/#{account.id}/ctwa_tracked_links",
         params: { name: 'Link inválido', inbox_id: api_inbox.id },
         headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Ctwa::TrackedLink.count).to eq(0)
  end

  it 'destroys a tracked link' do
    tracked_link = Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'QR Loja', code: 'ABC234')

    expect do
      delete "/api/v1/accounts/#{account.id}/ctwa_tracked_links/#{tracked_link.id}", headers: auth_headers(admin)
    end.to change(Ctwa::TrackedLink, :count).by(-1)

    expect(response).to have_http_status(:no_content)
  end

  describe 'modo site (#1011)' do
    let(:base_url) { "/api/v1/accounts/#{account.id}/ctwa_tracked_links" }
    let(:ad_url_params) do
      'utm_source=meta&utm_medium=paid&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}&utm_id={{campaign.id}}'
    end

    def create_website_link(origins: ['https://placement.com.br'])
      Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'LP Seguro Viagem', code: 'ABC234', usage: 'website',
                                allowed_origins: origins)
    end

    it 'cria um link de página com origens normalizadas, sem texto pré-preenchido, e devolve o que a tela precisa' do
      with_modified_env FRONTEND_URL: 'https://chat.hub2you.ai/' do
        post base_url, params: { name: 'LP Seguro Viagem', inbox_id: inbox.id, usage: 'website', prefilled_text: 'ignorado',
                                 allowed_origins: ['HTTPS://Placement.com.br/', 'http://localhost:4321'] },
                       headers: auth_headers(admin), as: :json
      end

      expect(response).to have_http_status(:created)
      payload = response.parsed_body['payload']
      tracked_link = Ctwa::TrackedLink.find(payload['id'])
      expect(tracked_link).to have_attributes(usage: 'website', prefilled_text: '',
                                              allowed_origins: ['https://placement.com.br', 'http://localhost:4321'])
      expect(payload).to include(
        'usage' => 'website',
        'allowed_origins' => ['https://placement.com.br', 'http://localhost:4321'],
        'last_signal_at' => nil,
        'signals_blocked' => false,
        'signal_url' => "https://chat.hub2you.ai/l/#{tracked_link.code}/clicks",
        'ad_url_params' => ad_url_params,
        'campaigns' => []
      )
    end

    it 'cria link direto por padrão, sem os campos do modo site' do
      post base_url, params: { name: 'QR Balcão', inbox_id: inbox.id, prefilled_text: 'Oi' }, headers: auth_headers(admin), as: :json

      payload = response.parsed_body['payload']
      expect(response).to have_http_status(:created)
      expect(payload).to include('usage' => 'direct', 'prefilled_text' => 'Oi', 'allowed_origins' => [], 'signal_url' => nil,
                                 'signals_blocked' => false, 'ad_url_params' => nil, 'campaigns' => [])
    end

    it 'recusa uso desconhecido e origens inválidas com 422, sem criar' do
      [
        { usage: 'popup', allowed_origins: [] },
        { usage: 'website', allowed_origins: ['http://placement.com.br'] },
        { usage: 'website', allowed_origins: ['https://placement.com.br/seguro'] },
        { usage: 'website', allowed_origins: ['https://placement.com.br?x=1'] },
        { usage: 'website', allowed_origins: ['ftp://placement.com.br'] },
        { usage: 'website', allowed_origins: ['placement.com.br'] },
        { usage: 'website', allowed_origins: Array.new(6) { |index| "https://site#{index}.com.br" } }
      ].each do |attrs|
        post base_url, params: { name: 'LP', inbox_id: inbox.id }.merge(attrs), headers: auth_headers(admin), as: :json

        expect(response).to have_http_status(:unprocessable_entity), attrs.inspect
      end
      expect(Ctwa::TrackedLink.count).to eq(0)
    end

    it 'só aceita http://localhost fora de produção' do
      tracked_link = Ctwa::TrackedLink.new(account: account, inbox: inbox, name: 'LP', usage: 'website',
                                           allowed_origins: ['http://localhost:4321'])
      expect(tracked_link).to be_valid

      allow(Rails.env).to receive(:production?).and_return(true)
      expect(tracked_link).not_to be_valid
      expect(tracked_link.errors[:allowed_origins].join).to include('http://localhost:4321')
    end

    it 'atualiza nome e origens autorizadas; uso e texto pré-preenchido do modo site não mudam' do
      tracked_link = create_website_link

      patch "#{base_url}/#{tracked_link.id}",
            params: { name: 'LP Viagem', usage: 'direct', prefilled_text: 'x',
                      allowed_origins: ['https://placement.com.br', 'https://www.placement.com.br:8443/'] },
            headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(tracked_link.reload).to have_attributes(
        name: 'LP Viagem', usage: 'website', prefilled_text: '',
        allowed_origins: ['https://placement.com.br', 'https://www.placement.com.br:8443']
      )
      expect(response.parsed_body['payload']['allowed_origins']).to eq(['https://placement.com.br', 'https://www.placement.com.br:8443'])
    end

    it 'limpa as origens com lista vazia (página desligada sem build) e recusa origem inválida sem mudar nada' do
      tracked_link = create_website_link

      patch "#{base_url}/#{tracked_link.id}", params: { allowed_origins: ['http://evil.example'] }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(tracked_link.reload.allowed_origins).to eq(['https://placement.com.br'])

      patch "#{base_url}/#{tracked_link.id}", params: { allowed_origins: [] }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
      expect(tracked_link.reload.allowed_origins).to eq([])
    end

    it 'atualiza o texto pré-preenchido do link direto' do
      tracked_link = Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'QR', code: 'XYZ789', prefilled_text: 'Oi')

      patch "#{base_url}/#{tracked_link.id}", params: { prefilled_text: 'Quero orçamento' }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(tracked_link.reload.prefilled_text).to eq('Quero orçamento')
    end

    it 'não deixa agente sem permissão de campanha atualizar, nem mexer em link de outra conta' do
      tracked_link = create_website_link
      agent = create(:user, account: account, role: :agent)

      patch "#{base_url}/#{tracked_link.id}", params: { name: 'Hack' }, headers: auth_headers(agent), as: :json
      expect(response).to have_http_status(:unauthorized)

      other_account = create(:account)
      other_admin = create(:user, :administrator, account: other_account)
      patch "/api/v1/accounts/#{other_account.id}/ctwa_tracked_links/#{tracked_link.id}", params: { name: 'Hack' },
                                                                                          headers: auth_headers(other_admin), as: :json
      expect(response).to have_http_status(:not_found)
      expect(tracked_link.reload.name).to eq('LP Seguro Viagem')
    end

    it 'mostra o resultado por campanha: cliques, conversas, cards ganhos e valor por moeda' do
      tracked_link = create_website_link
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      eua = { 'utm_campaign' => 'Viagem EUA', 'utm_id' => '120211' }
      conversations = Array.new(3) { create(:conversation, account: account, inbox: inbox) }

      travel_to(2.hours.ago) do
        create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'AAAA2222',
                                         params: { 'utm_campaign' => 'EUA antigo', 'utm_id' => '120211' }, campaign_key: '120211',
                                         conversation: conversations[0])
      end
      create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'BBBB3333', params: eua,
                                       campaign_key: '120211', conversation: conversations[1])
      create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'CCCC4444', params: eua,
                                       campaign_key: '120211', conversation: conversations[1])
      create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'DDDD5555', params: eua, campaign_key: '120211')
      create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'EEEE6666', params: {}, campaign_key: 'none',
                                       conversation: conversations[2])

      card_for = lambda do |conversation, status, cents, currency = 'BRL'|
        account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', conversation_id: conversation.id,
                                  inbox_id: conversation.inbox_id, contact_id: conversation.contact_id, status: status,
                                  value_cents: cents, currency: currency)
      end
      card_for.call(conversations[0], :won, 37_780)
      card_for.call(conversations[1], :won, 113_340)
      card_for.call(conversations[1], :won, 5_000, 'USD')
      card_for.call(conversations[1], :lost, 99_999)
      card_for.call(conversations[2], :open, 10_000)

      get base_url, headers: auth_headers(admin)

      campaigns = response.parsed_body['payload'].find { |link| link['id'] == tracked_link.id }['campaigns']
      # Último clique de cada campanha (#1068): o mais recente, não o de 2 horas atrás.
      latest = Ctwa::TrackedLinkClick.where(tracked_link: tracked_link, campaign_key: '120211').maximum(:created_at)
      expect(campaigns.first['last_clicked_at']).to eq(latest.iso8601)
      expect(campaigns.map { |row| row.except('last_clicked_at') }).to eq(
        [
          { 'campaign_key' => '120211', 'name' => 'Viagem EUA', 'clicks' => 4, 'conversations' => 2, 'won_cards' => 3,
            'won_value_by_currency' => { 'BRL' => 151_120, 'USD' => 5_000 } },
          { 'campaign_key' => 'none', 'name' => nil, 'clicks' => 1, 'conversations' => 1, 'won_cards' => 0,
            'won_value_by_currency' => {} }
        ]
      )
    end

    it 'agente com função de campanhas vê cliques e conversas, mas não a receita' do
      tracked_link = create_website_link
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'AAAA2222',
                                       params: { 'utm_id' => '120211' }, campaign_key: '120211', conversation: conversation)
      account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', conversation_id: conversation.id, inbox_id: inbox.id,
                                contact_id: conversation.contact_id, status: :won, value_cents: 37_780, currency: 'BRL')
      agent = create(:user, account: account, role: :agent)
      role = create(:custom_role, account: account, permissions: %w[campaign_view])
      AccountUser.find_by!(account: account, user: agent).update!(custom_role: role)

      get base_url, headers: auth_headers(agent)

      expect(response).to have_http_status(:ok)
      campaign = response.parsed_body['payload'].find { |link| link['id'] == tracked_link.id }['campaigns'].sole
      expect(campaign.except('last_clicked_at')).to eq('campaign_key' => '120211', 'name' => nil, 'clicks' => 1, 'conversations' => 1)
      expect(response.body).not_to include('won_value_by_currency', '37780')
    end

    it 'não mistura cliques de links ou contas diferentes no resultado por campanha' do
      tracked_link = create_website_link
      other_link = Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'LP 2', code: 'XYZ789', usage: 'website',
                                             allowed_origins: ['https://outra.com.br'])
      create(:ctwa_tracked_link_click, account: account, tracked_link: other_link, token: 'AAAA2222',
                                       params: { 'utm_id' => '120211' }, campaign_key: '120211')

      get base_url, headers: auth_headers(admin)

      payload = response.parsed_body['payload']
      expect(payload.find { |link| link['id'] == tracked_link.id }['campaigns']).to eq([])
      expect(payload.find { |link| link['id'] == other_link.id }['campaigns'].sole).to include('campaign_key' => '120211', 'clicks' => 1)
    end

    # O teto diário recusa também o aviso legítimo: a tela precisa mostrar o bloqueio.
    it 'avisa na tela quando o link atingiu o teto diário de avisos (página recusada agora)' do
      tracked_link = create_website_link
      stub_const('Ctwa::TrackedLink::SIGNALS_DAILY_LIMIT', 2)
      create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'AAAA2222')
      create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'BBBB3333', created_at: 25.hours.ago)

      get base_url, headers: auth_headers(admin)
      expect(response.parsed_body['payload'].sole['signals_blocked']).to be(false)

      create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: 'CCCC4444')
      get base_url, headers: auth_headers(admin)
      expect(response.parsed_body['payload'].sole['signals_blocked']).to be(true)
    end
  end
end
