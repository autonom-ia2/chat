require 'rails_helper'

# #1337: aviso da Meta sobre modelo chega na URL padrão do app (a Meta não manda evento de modelo para a URL da caixa)
# e vai para o job do fork. Mensagens, status de envio e chamadas seguem o caminho do Chatwoot.
RSpec.describe 'Webhooks::WhatsappController: avisos de modelo', type: :request do
  let(:app_secret) { 'segredo-do-app' }
  let(:waba_id) { '1029384756' }
  let(:url_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:template_change) do
    { field: 'message_template_status_update',
      value: { event: 'APPROVED', message_template_id: 594_425_479_261_596, message_template_name: 'aviso',
               message_template_language: 'pt_BR', reason: 'NONE' } }
  end
  let(:payload) { { object: 'whatsapp_business_account', entry: [{ id: waba_id, time: 1_791_000_000, changes: [template_change] }] } }
  let(:body) { payload.to_json }

  def signed(content, secret = app_secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, content)}"
  end

  # A factory troca o business_account_id da caixa Cloud: a WABA e o segredo são gravados depois.
  def waba_channel(secret)
    channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    channel.update_columns(provider_config: channel.provider_config.merge('business_account_id' => waba_id, 'app_secret' => secret)) # rubocop:disable Rails/SkipsModelValidations
    channel
  end

  def post_payload(content, signature: signed(content), env: { WHATSAPP_APP_SECRET: app_secret })
    headers = { 'CONTENT_TYPE' => 'application/json' }
    headers['X-Hub-Signature-256'] = signature if signature
    with_modified_env(env) { post "/webhooks/whatsapp/#{url_channel.phone_number}", params: content, headers: headers }
  end

  before do
    InstallationConfig.where(name: 'WHATSAPP_APP_SECRET').delete_all
    GlobalConfig.clear_cache
    allow(Whatsapp::Templates::WebhookJob).to receive(:perform_later)
    allow(Webhooks::WhatsappEventsJob).to receive(:perform_later)
  end

  it 'só mudanças de modelo: enfileira o job do fork com WABA, hora e o evento, e não o job de mensagens' do
    post_payload(body)

    expect(response).to have_http_status(:ok)
    expect(Webhooks::WhatsappEventsJob).not_to have_received(:perform_later)
    expect(Whatsapp::Templates::WebhookJob).to have_received(:perform_later).with(
      [hash_including('waba_id' => waba_id, 'time' => 1_791_000_000, 'field' => 'message_template_status_update',
                      'value' => hash_including('event' => 'APPROVED', 'message_template_id' => 594_425_479_261_596))]
    )
  end

  it 'várias entradas e os três tipos de aviso vão juntos num job só' do
    quality = { field: 'message_template_quality_update', value: { message_template_id: 1, new_quality_score: 'RED' } }
    category = { field: 'template_category_update', value: { message_template_id: 1, previous_category: 'UTILITY', new_category: 'MARKETING' } }
    payload[:entry] << { id: '555', time: 1_791_000_001, changes: [quality, category] }

    post_payload(payload.to_json)

    expect(Whatsapp::Templates::WebhookJob).to have_received(:perform_later).with(
      [hash_including('waba_id' => waba_id), hash_including('waba_id' => '555', 'field' => 'message_template_quality_update'),
       hash_including('waba_id' => '555', 'field' => 'template_category_update')]
    )
  end

  it 'POST misto (modelo + mensagem): segue inteiro pelo caminho atual, sem o job do fork' do
    message_change = { field: 'messages', value: { metadata: { phone_number_id: 'x', display_phone_number: '1' },
                                                   statuses: [{ id: 'wamid', status: 'failed' }] } }
    payload[:entry].first[:changes] << message_change

    post_payload(payload.to_json)

    expect(response).to have_http_status(:ok)
    expect(Webhooks::WhatsappEventsJob).to have_received(:perform_later)
    expect(Whatsapp::Templates::WebhookJob).not_to have_received(:perform_later)
  end

  it 'payload fora do formato (entrada que não é objeto) não é desviado: fica com o caminho do Chatwoot, como antes' do
    content = { object: 'whatsapp_business_account', entry: ['x'] }.to_json

    post_payload(content)

    expect(Whatsapp::Templates::WebhookJob).not_to have_received(:perform_later)
  end

  describe 'assinatura' do
    it 'sem assinatura: 401, mesmo quando a caixa da URL dispensaria a conferência' do
      post_payload(body, signature: nil)

      expect(response).to have_http_status(:unauthorized)
      expect(Whatsapp::Templates::WebhookJob).not_to have_received(:perform_later)
    end

    it 'assinatura errada: 401' do
      post_payload(body, signature: signed(body, 'outro'))

      expect(response).to have_http_status(:unauthorized)
    end

    it 'aceita o segredo guardado numa caixa da própria WABA' do
      waba_channel('segredo-da-caixa')

      post_payload(body, signature: signed(body, 'segredo-da-caixa'), env: {})

      expect(response).to have_http_status(:ok)
      expect(Whatsapp::Templates::WebhookJob).to have_received(:perform_later)
    end

    it 'não aceita o segredo da caixa da URL quando ela é de outra WABA (um cliente não muda modelo de outro)' do
      url_channel.update_columns(provider_config: url_channel.provider_config.merge('business_account_id' => 'outra', 'app_secret' => 'meu')) # rubocop:disable Rails/SkipsModelValidations

      post_payload(body, signature: signed(body, 'meu'), env: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it 'com duas WABAs no mesmo POST, o segredo de caixa precisa valer para as duas' do
      waba_channel('so-desta')
      payload[:entry] << { id: 'outra', time: 1, changes: [template_change] }
      content = payload.to_json

      post_payload(content, signature: signed(content, 'so-desta'), env: {})

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
