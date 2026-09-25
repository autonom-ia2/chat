require 'rails_helper'

RSpec.describe 'Autonomia prospecting leads API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account,
      provider: 'mock',
      provider_place_id: 'mock-place-1',
      name: 'Alpha Restaurante',
      phone: '+55 11 99999-8888',
      city: 'Sao Paulo',
      state: 'SP',
      country: 'BR'
    )
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  it 'converts a prospecting lead into a Chatwoot contact' do
    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/contact",
         headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload.dig('lead', 'contact_id')).to be_present
    expect(payload.dig('lead', 'contact_status')).to eq('created')
    expect(payload.dig('contact', 'phone_number')).to eq('+5511999998888')
    expect(lead.reload.contact_id).to eq(payload.dig('contact', 'id'))
  end

  it 'does not create a duplicate contact when called twice' do
    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/contact",
         headers: auth_headers(admin)
    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/contact",
         headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(account.contacts.count).to eq(1)
  end

  it 'creates a CRM card from a prospecting lead' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)

    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/crm_card",
         params: { crm_card: { pipeline_id: pipeline.id, stage_id: stage.id } },
         headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload.dig('lead', 'crm_card_id')).to be_present
    expect(payload.dig('lead', 'crm_status')).to eq('created')
    expect(payload.dig('crm_card', 'pipeline_id')).to eq(pipeline.id)
    expect(payload.dig('crm_card', 'stage_id')).to eq(stage.id)
    expect(lead.reload.crm_card_id).to eq(payload.dig('crm_card', 'id'))
  end

  it 'does not create a duplicate CRM card when called twice' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)

    2.times do
      post "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/crm_card",
           params: { crm_card: { pipeline_id: pipeline.id, stage_id: stage.id } },
           headers: auth_headers(admin)
    end

    expect(response).to have_http_status(:ok)
    expect(account.crm_cards.count).to eq(1)
  end

  it 'updates lead quality status and discard reason' do
    patch "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}",
          params: { lead: { status: 'discarded', discard_reason: 'Fora do perfil' } },
          headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload['status']).to eq('discarded')
    expect(payload['discard_reason']).to eq('Fora do perfil')
    expect(payload['source_label']).to eq('Mock')
    expect(lead.reload).to be_discarded
  end

  describe 'telefone de WhatsApp no payload pela tabela compartilhada com o front' do
    def show_lead
      get "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}", headers: auth_headers(admin)
      response.parsed_body['payload']
    end

    ProspectingPhoneContractCases.all.each do |item|
      it "#{item['caso']}: #{item['raw'].inspect} devolve #{item['e164'].inspect}" do
        ProspectingPhoneContractCases.apply_region!(account, item['region'])
        lead.update!(phone: item['raw'])

        payload = show_lead

        expect(payload['whatsapp_phone']).to eq(item['e164'])
        expect(payload['whatsapp_url']).to be_nil
      end
    end

    it 'monta o link do WhatsApp verificado a partir do número gravado na verificação' do
      lead.update!(phone: '(55) 99988-7766', metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5555999887766' } })

      payload = show_lead

      expect(payload['whatsapp_verified']).to be(true)
      expect(payload['whatsapp_url']).to eq('https://wa.me/5555999887766')
    end
  end

  # "Tem horário" do refino na tela usa o mesmo valor que o motor filtrou (#677).
  describe 'horário cadastrado no payload' do
    def opening_hours_flag
      get "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}", headers: auth_headers(admin)
      response.parsed_body.dig('payload', 'has_opening_hours')
    end

    it 'devolve a coluna gravada pelo provider' do
      lead.update!(has_opening_hours: true)

      expect(opening_hours_flag).to be(true)
    end

    it 'em lead gravado antes da coluna, usa regularOpeningHours do payload guardado' do
      lead.update!(raw_payload: { 'regularOpeningHours' => { 'weekdayDescriptions' => ['segunda-feira: 08:00'] } })
      expect(opening_hours_flag).to be(true)

      lead.update!(raw_payload: { 'currentOpeningHours' => { 'openNow' => true } })
      expect(opening_hours_flag).to be(false)
    end
  end

  # ENRIQ-69 (#682, E6): se uma busca troca o telefone enquanto o WAHA responde, a verificação manual não diz "tem
  # WhatsApp" de um número que já não é o do lead; responde o estado real, pendente e de novo na fila.
  describe 'verificação manual com o telefone trocado no meio' do
    let(:waha_env) { { 'WAHA_API_URL' => 'https://waha.test', 'WAHA_API_KEY' => 'chave-waha-teste' } }

    before do
      create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'sessao-prospeccao' })
      stub_request(:get, 'https://waha.test/api/contacts/check-exists')
        .with(query: { phone: '+5511999998888', session: 'sessao-prospeccao' })
        .to_return do
          Autonomia::Prospecting::Lead.where(id: lead.id).update_all(phone: '+55 11 97777-6666') # rubocop:disable Rails/SkipsModelValidations
          { status: 200, body: { numberExists: true, chatId: '5511999998888@c.us' }.to_json, headers: { 'Content-Type' => 'application/json' } }
        end
    end

    it 'responde pendente, sem o número antigo' do
      with_modified_env(waha_env) do
        post "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/whatsapp_verification",
             headers: auth_headers(admin)
      end

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload).to include('exists' => nil, 'pending' => true, 'phone' => nil, 'chat_id' => nil)
      expect(payload['lead']).to include('whatsapp_verification_status' => 'queued', 'whatsapp_verified' => false,
                                         'whatsapp_phone' => '+5511977776666', 'whatsapp_url' => nil)
    end

    it 'lead apagado enquanto o WAHA responde: 404, como o lead que já não existia' do
      stub_request(:get, 'https://waha.test/api/contacts/check-exists')
        .with(query: { phone: '+5511999998888', session: 'sessao-prospeccao' })
        .to_return do
          Autonomia::Prospecting::Lead.where(id: lead.id).delete_all
          { status: 200, body: { numberExists: true }.to_json, headers: { 'Content-Type' => 'application/json' } }
        end

      with_modified_env(waha_env) do
        post "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/#{lead.id}/whatsapp_verification",
             headers: auth_headers(admin)
      end

      expect(response).to have_http_status(:not_found)
    end
  end

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end
end
