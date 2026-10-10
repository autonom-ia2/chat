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
    Redis::Alfred.scan_each(match: 'crm:meta_ads:advisor:*') { |key| Redis::Alfred.delete(key) }
  end

  def spend_today(connection)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: Date.new(2026, 10, 6),
                                    currency: 'BRL', spend: 42.5, attribution_window: '7d_click', fetched_at: Time.current)
  end

  # 5 conversas de anúncio sem anúncio identificado: o rastreio falha e a ação do dia é `fix_tracking`.
  def untracked_conversations
    5.times do |index|
      conversation = create(:conversation, account: account)
      Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: SecureRandom.hex(4), origin: 'whatsapp',
                              certainty: 'unknown', touched_at: (index + 1).days.ago)
    end
  end

  def run_job_and_poll(accepted)
    Crm::Ai::InteractiveJob.perform_now(accepted['id'])
    get accepted['poll_url'], headers: auth_headers(admin)
    response.parsed_body
  end

  def post_daily_action(user = admin)
    post "#{path}/daily_action", params: { days: 7 }, headers: auth_headers(user), as: :json
  end

  describe 'POST daily_action' do
    let(:connection) { create_meta_ads_insights_connection(account) }
    let(:answer) do
      { applies: true, numbers_in_words: false,
        actions: [{ key: 'a1', headline: 'Arrume a origem das conversas.', body: 'Faltam {{unknown}} de {{conversations}} conversas.',
                    why: 'Só {{identified_pct}} delas têm o anúncio.' }] }
    end

    it 'pede à IA em segundo plano, devolve o Advice escrito e não chama de novo na próxima leitura' do
      spend_today(connection)
      untracked_conversations
      allow(client).to receive(:create).once.and_return(text: answer.to_json)

      expect { post_daily_action }.to have_enqueued_job(Crm::Ai::InteractiveJob)
      expect(response).to have_http_status(:accepted)

      result = run_job_and_poll(response.parsed_body)
      written = { 'status' => 'written', 'reason' => nil }
      expect(result).to include('status' => 'done', 'result' => include('daily_action' => include('writer' => written)))
      expect(result['result']['daily_action']['actions'].sole).to include(
        'kind' => 'fix_tracking', 'source' => 'ai', 'status' => 'open', 'body' => 'Faltam 5 de 5 conversas.', 'why' => 'Só 0% delas têm o anúncio.'
      )

      post_daily_action
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['daily_action']['actions'].sole).to include('source' => 'ai', 'kind' => 'fix_tracking')
      expect(client).to have_received(:create).once
    end

    it 'o job só escreve o run da própria conta' do
      connection
      other_run = Crm::MetaAdvisorRun.create!(account: create(:account), ad_account_id: '1', local_date: Date.new(2026, 10, 6), locale: 'en',
                                              signature: 'x', rules_version: 'f5.1', trigger: 'panel')
      operation = Crm::Ai::InteractiveOperation.new(
        'operation' => 'meta_ads_daily_action', 'inputs' => { 'run_id' => other_run.id, 'language' => 'en' }, 'account_id' => account.id,
        'account_user_id' => account.account_users.find_by(user: admin).id
      )

      operation.authorize!
      expect { operation.perform }.to raise_error(ActiveRecord::RecordNotFound)
      expect(other_run.reload.writer_status).to eq('pending')
    end

    it 'IA desligada fecha o run pela regra e responde na hora' do
      untracked_conversations
      connection

      with_modified_env CRM_AI_ENABLED: 'false' do
        post_daily_action
      end

      expect(response).to have_http_status(:ok)
      advice = response.parsed_body['daily_action']
      expect(advice['writer']).to eq('status' => 'rule', 'reason' => 'ai_unavailable')
      expect(advice['actions'].sole).to include('kind' => 'fix_tracking', 'source' => 'rule', 'headline' => nil)
    end

    it 'só com a ação de espera não chama a IA' do
      spend_today(connection)

      post_daily_action

      advice = response.parsed_body['daily_action']
      expect(advice['writer']).to eq('status' => 'rule', 'reason' => 'not_applicable')
      expect(advice['actions'].sole).to include('id' => nil, 'kind' => 'wait', 'ad_id' => ad_id)
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end

    it 'passado o teto do dia, fica com a regra sem reservar de novo' do
      untracked_conversations
      connection
      key = Crm::MetaAds::Advisor::Analysis.counter_key(account.id, Date.new(2026, 10, 6))
      Redis::Alfred.set(key, Crm::MetaAds::Advisor::Analysis::DAILY_LIMIT)

      post_daily_action

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['daily_action']['writer']).to eq('status' => 'rule', 'reason' => 'daily_limit')
      expect(Redis::Alfred.get(key).to_i).to eq(Crm::MetaAds::Advisor::Analysis::DAILY_LIMIT)
    end

    it 'sem conexão devolve vazio' do
      post_daily_action

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('daily_action' => nil)
    end

    it 'agente recebe 403' do
      post_daily_action(agent)

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
