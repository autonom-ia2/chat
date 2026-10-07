require 'rails_helper'

# Anúncios da Meta, F4a (#1100): ação do dia e mensagem sugerida pela IA. Só administrador; nada é enviado.
RSpec.describe 'CRM meta_ads_connection AI (F4a)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      travel_to(Time.zone.parse('2026-10-06T15:00:00-03:00')) { example.run }
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:ad_id) { '120254710362980416' }
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: credential) }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  after do
    Redis::Alfred.scan_each(match: "#{Crm::MetaAds::Panel::AiActionCache::PREFIX}:*") { |key| Redis::Alfred.delete(key) }
  end

  def spend_today(connection)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: Date.new(2026, 10, 6),
                                    currency: 'BRL', spend: 42.5, attribution_window: '7d_click', fetched_at: Time.current)
  end

  def run_job_and_poll(accepted)
    Crm::Ai::InteractiveJob.perform_now(accepted['id'])
    get accepted['poll_url'], headers: auth_headers(admin)
    response.parsed_body
  end

  describe 'POST daily_action' do
    let(:connection) { create_meta_ads_insights_connection(account) }
    let(:answer) do
      { applies: true, kind: 'wait', ad_id: ad_id, headline: 'Deixe o anúncio rodar mais uns dias.',
        body: 'Ainda é cedo para mexer.', why: 'Ele gastou R$ 42,50 e ainda não tem conversas suficientes.' }
    end

    it 'pede à IA em segundo plano, devolve o texto dela e guarda para a próxima leitura do dia' do
      spend_today(connection)
      allow(client).to receive(:create).once.and_return(text: answer.to_json)

      expect do
        post "#{path}/daily_action", params: { days: 7 }, headers: auth_headers(admin), as: :json
      end.to have_enqueued_job(Crm::Ai::InteractiveJob)
      expect(response).to have_http_status(:accepted)

      result = run_job_and_poll(response.parsed_body)
      expect(result['status']).to eq('done')
      expect(result['result']['daily_action']).to include('source' => 'ai', 'kind' => 'wait', 'ad_id' => ad_id, 'days' => 7,
                                                          'headline' => 'Deixe o anúncio rodar mais uns dias.')

      post "#{path}/daily_action", params: { days: 7 }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['daily_action']).to include('source' => 'ai', 'kind' => 'wait')
      expect(client).to have_received(:create).once
    end

    it 'IA desligada responde a regra na hora' do
      spend_today(connection)

      with_modified_env CRM_AI_ENABLED: 'false' do
        post "#{path}/daily_action", params: { days: 7 }, headers: auth_headers(admin), as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['daily_action']).to include('source' => 'rule', 'reason' => 'ai_unavailable', 'kind' => 'wait', 'days' => 7)
    end

    it 'sem nada no período não chama a IA' do
      connection

      post "#{path}/daily_action", params: { days: 30 }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['daily_action']).to include('source' => 'rule', 'reason' => 'not_applicable', 'kind' => 'no_data')
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'passado o teto do dia, fica com a regra' do
      spend_today(connection)
      Crm::MetaAds::Panel::AiActionCache::DAILY_LIMIT.times do
        post "#{path}/daily_action", params: { days: 7 }, headers: auth_headers(admin), as: :json
        expect(response).to have_http_status(:accepted)
      end

      post "#{path}/daily_action", params: { days: 7 }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['daily_action']).to include('source' => 'rule', 'reason' => 'daily_limit')
    end

    it 'sem conexão devolve vazio' do
      post "#{path}/daily_action", params: { days: 7 }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('daily_action' => nil)
    end

    it 'agente recebe 403' do
      post "#{path}/daily_action", params: { days: 7 }, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'forbidden')
    end
  end

  describe 'POST quote_message' do
    let(:connection) { create_meta_ads_insights_connection(account) }
    let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
    let(:quote_stage) do
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Proposta', position: 1, metadata: { 'funnel_stage_type' => 'opportunity' })
    end
    let(:conversation) { create(:conversation, account: account) }
    let(:card) do
      Crm::Card.create!(account: account, pipeline: pipeline, stage: quote_stage, title: 'Cotação', currency: 'BRL', value_cents: 150_000,
                        primary_conversation: conversation, last_message_at: 5.days.ago)
    end

    before do
      Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: SecureRandom.hex(4), origin: 'whatsapp',
                              certainty: 'ad', ad_id: ad_id, touched_at: 6.days.ago)
      create(:message, account: account, conversation: conversation, message_type: :incoming,
                       content: 'Pode me mandar o valor com a instalação inclusa?', created_at: 5.days.ago)
    end

    it 'escreve a mensagem em segundo plano e não envia nada' do
      connection
      suggestion = { applies: true, reason: 'none', message: 'Oi! Posso te mandar o valor com a instalação?',
                     source_quote: 'o valor com a instalação inclusa', includes_outside_contact: false }
      allow(client).to receive(:create).and_return(text: suggestion.to_json)

      expect do
        post "#{path}/quote_message", params: { card_id: card.id }, headers: auth_headers(admin), as: :json
      end.to have_enqueued_job(Crm::Ai::InteractiveJob)
      expect(response).to have_http_status(:accepted)

      result = nil
      expect { result = run_job_and_poll(response.parsed_body) }.not_to change(Message, :count)
      expect(result['result']['quote_message']).to eq(
        'card_id' => card.id, 'conversation_id' => conversation.id, 'applies' => true, 'reason' => nil,
        'message' => suggestion[:message], 'source_quote' => suggestion[:source_quote]
      )
    end

    it 'IA desligada responde na hora, sem a IA' do
      connection

      with_modified_env CRM_AI_ENABLED: 'false' do
        post "#{path}/quote_message", params: { card_id: card.id }, headers: auth_headers(admin), as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['quote_message']).to include('card_id' => card.id, 'applies' => false, 'reason' => 'ai_unavailable')
    end

    it 'card que não está parado recebe 422' do
      connection
      card.update!(last_message_at: 1.hour.ago)

      post "#{path}/quote_message", params: { card_id: card.id }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'card_not_stalled')
    end

    it 'card de outra conta é card_not_found' do
      connection
      other = create(:account)
      other_pipeline, other_stage = create_crm_pipeline(account: other, user: create(:user, account: other))
      foreign = Crm::Card.create!(account: other, pipeline: other_pipeline, stage: other_stage, title: 'X', currency: 'BRL')

      post "#{path}/quote_message", params: { card_id: foreign.id }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body).to eq('error' => 'card_not_found')
    end

    it 'sem conexão nenhum card está parado' do
      post "#{path}/quote_message", params: { card_id: card.id }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body).to eq('error' => 'card_not_stalled')
    end

    it 'agente recebe 403' do
      post "#{path}/quote_message", params: { card_id: card.id }, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
