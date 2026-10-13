# A queda para o modelo da conversa aberta (#1335). Prepend em Whatsapp::IncomingMessageBaseService (o aviso de status
# da Meta), em config/initializers/campaign_journey.rb. A Meta aceita o texto livre e só depois avisa, pelo status
# `failed` com o código 131047, que a janela já tinha fechado. Nesse caso a pessoa recebe o modelo da campanha, uma vez
# só (fell_back_at), num job. Não cai para o modelo quando o Híbrido já entregou o texto pelo WhatsApp API
# (WhatsappHybrid::CloudFailureFallback, que roda no mesmo aviso e marca a mensagem com whatsapp_transport_fallback).
module CampaignJourney::ConversaAberta::Queda
  WINDOW_CLOSED_CODE = 131_047

  private

  def process_statuses
    super
    pedir_modelo(@processed_params[:statuses].first)
  end

  def pedir_modelo(status)
    return unless janela_fechada?(status)

    delivery = CampaignFreeTextDelivery.find_by(inbox_id: inbox.id, source_id: status[:id].to_s, fell_back_at: nil)
    return if delivery.nil? || entregue_pelo_hibrido?(delivery)

    CampaignJourney::ConversaAberta::QuedaJob.perform_later(delivery.id)
  end

  def janela_fechada?(status)
    status[:status].to_s == 'failed' && Array(status[:errors]).any? { |error| error[:code].to_i == WINDOW_CLOSED_CODE }
  end

  def entregue_pelo_hibrido?(delivery)
    message = Message.find_by(inbox_id: delivery.inbox_id, source_id: delivery.source_id)
    message.present? && message.content_attributes.to_h['whatsapp_transport_fallback'].present?
  end
end
