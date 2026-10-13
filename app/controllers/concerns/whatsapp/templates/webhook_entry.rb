# Entrada dos avisos de modelo da Meta no webhook do WhatsApp Cloud (#1337). Prependido em `Webhooks::WhatsappController`
# por `config/initializers/whatsapp_templates.rb`; o arquivo do Chatwoot fica intacto.
#
# A Meta manda aviso de modelo sempre para a URL padrão do app (não respeita a URL da caixa) e sem número no payload: no
# `Webhooks::WhatsappEventsJob` ele não acha caixa e é descartado. Aqui, o POST em que TODAS as mudanças são de modelo vai
# para o `Whatsapp::Templates::WebhookJob`. POST com qualquer outra mudança (mensagens, status de envio, chamadas) segue
# inteiro pelo caminho do Chatwoot (o aviso que vier junto se perde e o sync seguinte corrige). A lista
# `INACTIVE_WHATSAPP_NUMBERS` não vale aqui: ela é do número da URL, e o aviso de modelo é da WABA.
#
# Assinatura: obrigatória para aviso de modelo, mesmo quando a caixa da URL dispensaria. Vale o segredo do app
# (`WHATSAPP_APP_SECRET`) ou um segredo guardado em caixa de TODAS as WABAs do POST; nunca o da caixa da URL, que seria
# de outro cliente (quem tem o próprio segredo não pode mudar modelo da WABA de outro).
module Whatsapp::Templates::WebhookEntry
  def process_payload
    return super unless template_events_only?

    Whatsapp::Templates::WebhookJob.perform_later(template_changes)
    head :ok
  end

  private

  def template_events_only?
    return @template_events_only if defined?(@template_events_only)

    return @template_events_only = false unless params[:object] == 'whatsapp_business_account'

    # Payload fora do formato (entrada ou mudança que não é objeto) segue pelo caminho do Chatwoot, como antes.
    changes = template_entries.flat_map { |entry| params_hash?(entry) ? Array(entry.fetch(:changes, [])) : [nil] }
    @template_events_only = changes.present? && changes.all? { |change| template_change?(change) }
  end

  def template_change?(change)
    params_hash?(change) && Whatsapp::Templates::WebhookEvent::FIELD_KINDS.key?(change[:field])
  end

  def params_hash?(value)
    value.is_a?(ActionController::Parameters)
  end

  def template_entries
    Array(params.fetch(:entry, []))
  end

  def template_changes
    template_entries.flat_map do |entry|
      entry.fetch(:changes, []).map do |change|
        { 'waba_id' => entry[:id].to_s, 'time' => entry[:time].to_i, 'field' => change[:field].to_s,
          'value' => change[:value].respond_to?(:to_unsafe_h) ? change[:value].to_unsafe_h.to_h : {} }
      end
    end
  end

  def meta_signature_verification_required?
    template_events_only? || super
  end

  def meta_app_secrets
    return super unless template_events_only?

    [GlobalConfigService.load('WHATSAPP_APP_SECRET', nil), *secrets_shared_by_payload_wabas]
  end

  def secrets_shared_by_payload_wabas
    waba_ids = template_entries.map { |entry| entry[:id].to_s }.uniq
    return [] if waba_ids.empty? || waba_ids.any?(&:blank?)

    waba_ids.map { |waba_id| waba_channel_secrets(waba_id) }.reduce(:&)
  end

  def waba_channel_secrets(waba_id)
    Channel::Whatsapp.where(provider: 'whatsapp_cloud').where("provider_config ->> 'business_account_id' = ?", waba_id)
                     .flat_map { |channel| channel_meta_app_secrets(channel) }.uniq
  end
end
