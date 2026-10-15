# A queda para o modelo da conversa aberta (#1335). Prepend em Whatsapp::IncomingMessageBaseService (o aviso de status
# da Meta), em config/initializers/campaign_journey.rb. A Meta aceita o texto livre e só depois avisa, pelo status
# `failed` com o código 131047, que a janela já tinha fechado. Nesse caso a pessoa recebe o modelo da campanha, uma vez
# só (fell_back_at), num job. Quando o Híbrido ASSUMIU o envio do texto pelo WhatsApp API
# (WhatsappHybrid::CloudFailureFallback, que roda no mesmo aviso e marca a mensagem com whatsapp_transport_fallback),
# quem decide é a CampaignJourney::ConversaAberta::QuedaHibrido, pelo resultado do envio (#1453): só `failed` vira modelo.
# A entrega é achada pelo source_id do aviso (o wamid gravado no envio); a mensagem da conversa, pelo id gravado na
# entrega, porque o Híbrido troca o source_id dela pelo id do WAHA.
module CampaignJourney::ConversaAberta::Queda
  WINDOW_CLOSED_CODE = 131_047

  private

  # `ensure`: se o Híbrido falhar ao reenviar pelo WhatsApp API (ele volta a mensagem para a falha e levanta), a pessoa
  # ainda recebe o modelo.
  def process_statuses
    super
  ensure
    pedir_modelo_sem_levantar
  end

  # Roda no `ensure`: nunca levanta, para não esconder a exceção original do `super`.
  def pedir_modelo_sem_levantar
    status = Array(@processed_params.try(:[], :statuses)).first
    pedir_modelo(status) if status
  rescue StandardError => e
    Rails.logger.error "[ConversaAberta] queda para o modelo não pedida source_id=#{status.try(:[], :id)}: #{e.class}"
  end

  def pedir_modelo(status)
    return unless janela_fechada?(status)

    delivery = CampaignFreeTextDelivery.find_by(inbox_id: inbox.id, source_id: status[:id].to_s, fell_back_at: nil)
    CampaignJourney::ConversaAberta::QuedaHibrido.new(delivery).seguir if delivery
  end

  def janela_fechada?(status)
    status[:status].to_s == 'failed' && Array(status[:errors]).any? { |error| error[:code].to_i == WINDOW_CLOSED_CODE }
  end
end
