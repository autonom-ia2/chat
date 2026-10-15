# A queda da conversa aberta quando o WhatsApp Híbrido assumiu o texto recusado no 131047 (#1453). O reenvio do Híbrido é
# síncrono (WhatsappHybrid::CloudFailureFallback roda o WebTransport dentro do aviso), então, no `ensure` da Queda, o
# resultado já está gravado na Message, sob trava, por outra instância dela: aqui ela é sempre relida do banco pelo
# message_id da entrega. Decide pelo resultado estável do WebTransport (whatsapp_transport_outcome, #1349):
# - sem a marca do Híbrido, ou com a marca e erro antes de o WebTransport marcar o envio (whatsapp_transport): o modelo;
# - `failed` (nada saiu): o modelo;
# - `throttled` (o Híbrido tenta de novo em 15 s): o ConferenciaHibridoJob relê depois, com teto de conferências;
# - `accepted` (saiu) ou `uncertain` (pode ter saído): nunca o modelo (seria mensagem dupla); vai ao log;
# - envio marcado e sem resultado (erro inesperado dali em diante, mesmo pouco antes do pedido): nunca o modelo, porque
#   pode ter saído; aviso no log. Conservador: pode haver perda, nunca mensagem dupla.
# O modelo sai pelo QuedaJob: uma vez só (fell_back_at, sob trava) e com as mesmas travas do disparo.
class CampaignJourney::ConversaAberta::QuedaHibrido
  FALLBACK_KEY = 'whatsapp_transport_fallback'.freeze

  # Chamado pelo WebTransport depois de uma falha certa (também a que chega na nova tentativa do throttled).
  def self.after_transport_failure(message)
    return if message.content_attributes.to_h[FALLBACK_KEY].blank?

    delivery = CampaignFreeTextDelivery.find_by(message_id: message.id, inbox_id: message.inbox_id, fell_back_at: nil)
    new(delivery).seguir if delivery
  end

  def initialize(delivery)
    @delivery = delivery
  end

  # tentativa: quantas conferências do `throttled` já rodaram (0 no aviso da Meta).
  def seguir(tentativa = 0)
    case decisao
    when :modelo then CampaignJourney::ConversaAberta::QuedaJob.perform_later(@delivery.id)
    when :conferir then conferir_depois(tentativa)
    when :sem_resultado then registrar(:warn, 'o Híbrido chamou o motor e não gravou resultado; pode ter saído')
    else registrar(:info, 'o Híbrido assumiu o texto')
    end
  end

  private

  def decisao
    return :modelo if attributes[FALLBACK_KEY].blank?

    case outcome
    when 'failed' then :modelo
    when 'throttled' then :conferir
    when nil then attributes['whatsapp_transport'] == 'web' ? :sem_resultado : :modelo
    else :nada
    end
  end

  def conferir_depois(tentativa)
    job = CampaignJourney::ConversaAberta::ConferenciaHibridoJob
    return registrar(:warn, "ainda throttled depois de #{tentativa} conferências") if tentativa >= job::TENTATIVAS

    job.set(wait: job::ESPERA * (2**tentativa)).perform_later(@delivery.id, tentativa + 1)
  end

  def registrar(level, motivo)
    Rails.logger.public_send(level, "[ConversaAberta] queda sem modelo delivery=#{@delivery.id} outcome=#{outcome || 'ausente'}: #{motivo}")
  end

  def outcome
    attributes[WhatsappHybrid::WebTransport::OUTCOME_KEY]
  end

  def attributes
    @attributes ||= begin
      message = Message.find_by(id: @delivery.message_id, inbox_id: @delivery.inbox_id) if @delivery.message_id.present?
      message ? message.content_attributes.to_h : {}
    end
  end
end
