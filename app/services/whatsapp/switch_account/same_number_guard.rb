# chat#1217 — Trocar a caixa de conta do WhatsApp (outra WABA, outro portfólio da Meta).
# Prepend em Whatsapp::EmbeddedSignupService:
# - antes de gravar a credencial nova numa caixa existente, confere que o Facebook devolveu o mesmo número
#   da caixa e falha com um erro tipado, que a tela traduz para "esse não é o número desta caixa". O
#   Whatsapp::ReauthorizationService do Chatwoot faz a mesma conferência, mas com um StandardError sem tipo;
# - quando a conta (WABA) mudou, descarta os modelos de mensagem da conta antiga e busca os da nova. A
#   sincronização do Chatwoot não grava lista vazia, e a caixa continuaria oferecendo modelos que não
#   existem na conta nova.
module Whatsapp::SwitchAccount::SameNumberGuard
  private

  def create_or_reauthorize_channel(access_token, phone_info)
    return super if @inbox_id.blank?

    ensure_same_phone_number!(phone_info)
    previous_waba_id = reauthorizing_channel&.waba_id
    channel = super
    refresh_templates_after_switch(channel) if previous_waba_id.present? && previous_waba_id != @waba_id
    channel
  end

  def ensure_same_phone_number!(phone_info)
    expected = reauthorizing_channel&.phone_number
    return if expected.blank? || phone_info[:phone_number] == expected

    raise Whatsapp::SwitchAccount::PhoneNumberMismatchError.new(expected: expected, received: phone_info[:phone_number])
  end

  def refresh_templates_after_switch(channel)
    # rubocop:disable Rails/SkipsModelValidations
    channel.update_columns(message_templates: [], message_templates_last_updated: nil)
    # rubocop:enable Rails/SkipsModelValidations
    Channels::Whatsapp::TemplatesSyncJob.perform_later(channel)
  end
end
