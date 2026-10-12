require 'rails_helper'

# Card do follow-up com o WhatsApp Híbrido (chat#1349, PR B): o endpoint de janela avisa se o texto pode sair pelo
# WhatsApp API, o servidor aceita criar sem modelo e o cliente não consegue forjar o transporte.
RSpec.describe 'CRM follow-ups com WhatsApp Híbrido', type: :request do
  include CrmHybridHelpers

  around do |example|
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*', CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let!(:scenario) { build_crm_hybrid_scenario }
  let(:account) { scenario[:account] }
  let(:user) { scenario[:user] }
  let(:base_url) { "/api/v1/accounts/#{account.id}/crm/follow_ups" }

  def window_for(conversation, at: 2.hours.from_now)
    get "#{base_url}/messaging_window", params: { conversation_id: conversation.id, at: at.iso8601 }, headers: auth_headers(user)
    response.parsed_body
  end

  def follow_up_params(metadata)
    { follow_up: { card_id: scenario[:card].id, conversation_id: scenario[:conversation].id, title: 'Retomar',
                   due_at: 2.hours.from_now.iso8601, timezone: 'UTC', automation_mode: 'auto_send_message', metadata: metadata } }
  end

  describe 'GET messaging_window' do
    it 'avisa que o WhatsApp API está disponível fora das 24h com o Híbrido pronto' do
      body = window_for(scenario[:conversation])

      expect(response).to have_http_status(:ok)
      expect(body).to include('requires_template' => true, 'whatsapp_native_inbox' => true, 'whatsapp_api_available' => true)
    end

    it 'não avisa dentro das 24h (a sessão oficial resolve)' do
      inside = build_crm_hybrid_scenario(last_inbound_ago: 1.hour.ago)
      user_inside = inside[:user]
      get "/api/v1/accounts/#{inside[:account].id}/crm/follow_ups/messaging_window",
          params: { conversation_id: inside[:conversation].id, at: 1.minute.from_now.iso8601 }, headers: auth_headers(user_inside)

      expect(response.parsed_body).to include('requires_template' => false, 'whatsapp_api_available' => false)
    end

    it 'não avisa com o Híbrido desconectado' do
      scenario[:connection].update!(status: 'disconnected')

      expect(window_for(scenario[:conversation])).to include('requires_template' => true, 'whatsapp_api_available' => false)
    end

    it 'não avisa com a origem crm_follow_up desligada' do
      scenario[:connection].update!(disabled_origins: ['crm_follow_up'])

      expect(window_for(scenario[:conversation])).to include('whatsapp_api_available' => false)
    end

    it 'não avisa em caixa sem Híbrido' do
      plain = build_crm_hybrid_scenario(hybrid: false)
      get "#{base_url.sub(account.id.to_s, plain[:account].id.to_s)}/messaging_window",
          params: { conversation_id: plain[:conversation].id, at: 2.hours.from_now.iso8601 }, headers: auth_headers(plain[:user])

      expect(response.parsed_body).to include('requires_template' => true, 'whatsapp_api_available' => false)
    end
  end

  describe 'POST create' do
    it 'cria sem modelo fora das 24h quando o Híbrido está pronto' do
      post base_url, params: follow_up_params({ message_body: 'Oi! Conseguiu ver o orçamento?' }), headers: auth_headers(user)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['payload']['metadata']).to include('message_body' => 'Oi! Conseguiu ver o orçamento?')
    end

    it 'recusa sem modelo quando o Híbrido caiu' do
      scenario[:connection].update!(status: 'disconnected')

      post base_url, params: follow_up_params({ message_body: 'Oi!' }), headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'descarta delivery_transport e a razão do Híbrido vindos do cliente' do
      metadata = { message_body: 'Oi!', source: 'ai_followup', delivery_transport: 'whatsapp_api',
                   hybrid_free_form_reason: 'no_candidates' }
      post base_url, params: follow_up_params(metadata), headers: auth_headers(user)

      expect(response).to have_http_status(:created)
      expect(Crm::FollowUp.find(response.parsed_body['payload']['id']).metadata.keys).not_to include('delivery_transport', 'hybrid_free_form_reason')
    end
  end

  describe 'PATCH update' do
    it 'descarta delivery_transport vindo do cliente ao editar o follow-up' do
      post base_url, params: follow_up_params({ message_body: 'Oi!' }), headers: auth_headers(user)
      id = response.parsed_body['payload']['id']

      patch "#{base_url}/#{id}", params: { follow_up: { metadata: { message_body: 'Oi de novo', source: 'ai_followup',
                                                                    delivery_transport: 'whatsapp_api' } } },
                                 headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      stored = Crm::FollowUp.find(id).metadata
      expect(stored).to include('message_body' => 'Oi de novo')
      expect(stored.keys).not_to include('delivery_transport')
    end
  end
end
