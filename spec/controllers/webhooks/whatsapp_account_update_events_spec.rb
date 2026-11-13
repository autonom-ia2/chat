require 'rails_helper'

# #2907: o aviso `account_update` chega na URL padrão do app, sem número no payload, e vai para o job do fork. Assinatura
# do app obrigatória. POST misto segue o caminho do Chatwoot.
RSpec.describe 'Webhooks::WhatsappController: aviso de acesso à conta', type: :request do
  let(:app_secret) { 'segredo-do-app' }
  let(:url_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account_update) { { field: 'account_update', value: { event: 'PARTNER_REMOVED', waba_info: { waba_id: '980198427658004' } } } }
  let(:payload) { { object: 'whatsapp_business_account', entry: [{ id: '2949482758682047', time: 1_748_477_359, changes: [account_update] }] } }

  def post_payload(content, secret: app_secret)
    headers = { 'CONTENT_TYPE' => 'application/json',
                'X-Hub-Signature-256' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, content)}" }
    with_modified_env(WHATSAPP_APP_SECRET: app_secret) { post "/webhooks/whatsapp/#{url_channel.phone_number}", params: content, headers: headers }
  end

  before do
    InstallationConfig.where(name: 'WHATSAPP_APP_SECRET').delete_all
    GlobalConfig.clear_cache
    allow(Whatsapp::AccessLoss::AccountUpdateJob).to receive(:perform_later)
    allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
  end

  it 'só account_update: enfileira o job do fork com entry.id e o valor, e não o job de mensagens' do
    post_payload(payload.to_json)

    expect(response).to have_http_status(:ok)
    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    expect(Whatsapp::AccessLoss::AccountUpdateJob).to have_received(:perform_later).with(
      [{ 'entry_id' => '2949482758682047', 'value' => { 'event' => 'PARTNER_REMOVED', 'waba_info' => { 'waba_id' => '980198427658004' } } }]
    )
  end

  it 'o conteúdo sai do corpo assinado: query string com outro entry não muda o que chega ao job' do
    content = payload.to_json
    headers = { 'CONTENT_TYPE' => 'application/json',
                'X-Hub-Signature-256' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret, content)}" }
    query = { entry: [{ id: 'forjado', changes: [{ field: 'account_update', value: { event: 'ACCOUNT_DELETED' } }] }] }.to_query
    with_modified_env(WHATSAPP_APP_SECRET: app_secret) do
      post "/webhooks/whatsapp/#{url_channel.phone_number}?#{query}", params: content, headers: headers
    end

    expect(Whatsapp::AccessLoss::AccountUpdateJob).to have_received(:perform_later).with(
      [{ 'entry_id' => '2949482758682047', 'value' => { 'event' => 'PARTNER_REMOVED', 'waba_info' => { 'waba_id' => '980198427658004' } } }]
    )
  end

  it 'value fora do formato chega ao job como hash vazio (sem 500)' do
    payload[:entry].first[:changes] = [{ field: 'account_update', value: 'x' }]

    post_payload(payload.to_json)

    expect(response).to have_http_status(:ok)
    expect(Whatsapp::AccessLoss::AccountUpdateJob).to have_received(:perform_later).with([{ 'entry_id' => '2949482758682047', 'value' => {} }])
  end

  it 'sem assinatura: recusa com 401' do
    url = "/webhooks/whatsapp/#{url_channel.phone_number}"
    with_modified_env(WHATSAPP_APP_SECRET: app_secret) { post url, params: payload.to_json, headers: { 'CONTENT_TYPE' => 'application/json' } }

    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::AccessLoss::AccountUpdateJob).not_to have_received(:perform_later)
  end

  it 'segredo do app vazio: recusa com 401 (fecha, não abre)' do
    content = payload.to_json
    headers = { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', '', content)}" }
    with_modified_env(WHATSAPP_APP_SECRET: '') { post "/webhooks/whatsapp/#{url_channel.phone_number}", params: content, headers: headers }

    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::AccessLoss::AccountUpdateJob).not_to have_received(:perform_later)
  end

  it 'assinatura de outro segredo: recusa com 401 e não enfileira nada' do
    post_payload(payload.to_json, secret: 'outro')

    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::AccessLoss::AccountUpdateJob).not_to have_received(:perform_later)
  end

  it 'POST misto (account_update + mensagem): segue inteiro pelo caminho atual' do
    message_change = { field: 'messages', value: { metadata: { phone_number_id: 'x', display_phone_number: '1' },
                                                   statuses: [{ id: 'wamid', status: 'read' }] } }
    payload[:entry].first[:changes] << message_change

    post_payload(payload.to_json)

    expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later)
    expect(Whatsapp::AccessLoss::AccountUpdateJob).not_to have_received(:perform_later)
  end

  it 'aviso de modelo continua indo para o job de modelos (as duas entradas convivem)' do
    allow(Whatsapp::Templates::WebhookJob).to receive(:perform_later)
    template = { field: 'message_template_status_update', value: { event: 'APPROVED', message_template_id: 1 } }

    post_payload({ object: 'whatsapp_business_account', entry: [{ id: '1', time: 1, changes: [template] }] }.to_json)

    expect(Whatsapp::Templates::WebhookJob).to have_received(:perform_later)
    expect(Whatsapp::AccessLoss::AccountUpdateJob).not_to have_received(:perform_later)
  end
end
