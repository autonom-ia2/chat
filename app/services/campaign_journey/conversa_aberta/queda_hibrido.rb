# A queda da conversa aberta quando o WhatsApp Híbrido assumiu o texto recusado no 131047 (#1453). O reenvio do Híbrido é
# síncrono (WhatsappHybrid::CloudFailureFallback roda o WebTransport dentro do aviso), então, no `ensure` da Queda, o
# resultado já está gravado na Message, sob trava, por outra instância dela: aqui ela é sempre relida do banco pelo
# message_id da entrega. Decide pelo resultado do WebTransport (whatsapp_transport_outcome, #1349):
# - sem a marca do Híbrido: o modelo;
# - `failed` (nada saiu): o modelo;
# - `throttled` (o Híbrido tenta de novo a cada 15 s, com teto): o ConferenciaHibridoJob relê depois; na última leitura,
#   depois do teto do Híbrido, se ainda estiver `throttled`, fecha como falha e manda o modelo;
# - `accepted` (saiu) ou `uncertain` (pode ter saído): nunca o modelo (seria mensagem dupla); vai ao log;
# - `pending` ou sem resultado com a marca: o Híbrido ainda está enviando (ou parou no meio); nunca o modelo, aviso no log.
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
    when :modelo then pedir_modelo
    when :conferir then conferir_depois(tentativa)
    when :sem_resultado then registrar(:warn, 'o Híbrido ainda não gravou resultado; pode sair')
    else registrar(:info, 'o Híbrido assumiu o texto')
    end
  end

  private

  def decisao
    return :modelo if attributes[FALLBACK_KEY].blank?

    case outcome
    when 'failed' then :modelo
    when 'throttled' then :conferir
    when 'accepted', 'uncertain' then :nada
    else :sem_resultado
    end
  end

  def pedir_modelo
    CampaignJourney::ConversaAberta::QuedaJob.perform_later(@delivery.id)
  end

  def conferir_depois(tentativa)
    job = CampaignJourney::ConversaAberta::ConferenciaHibridoJob
    return desistir_do_hibrido(tentativa) if tentativa >= job::ESPERAS.size

    job.set(wait: job::ESPERAS[tentativa]).perform_later(@delivery.id, tentativa + 1)
  end

  # A última conferência roda depois do teto de novas tentativas do Híbrido: ainda `throttled`, a nova tentativa não
  # está mais na fila. Fecha sob trava (WhatsappHybrid::UnexpectedErrorOutcome) e, se nada saiu, manda o modelo.
  def desistir_do_hibrido(tentativa)
    final = WhatsappHybrid::UnexpectedErrorOutcome.settle!(message, external_error: WhatsappHybrid::WebTransport::THROTTLED_OUT_ERROR)
    registrar(:warn, "ainda throttled depois de #{tentativa} conferências; fechado como #{final}")
    pedir_modelo if final == 'failed'
  end

  def registrar(level, motivo)
    Rails.logger.public_send(level, "[ConversaAberta] queda delivery=#{@delivery.id} message=#{@delivery.message_id} " \
                                    "outcome=#{outcome || 'ausente'}: #{motivo}")
  end

  def outcome
    attributes[WhatsappHybrid::WebTransport::OUTCOME_KEY]
  end

  def attributes
    @attributes ||= message ? message.content_attributes.to_h : {}
  end

  def message
    return @message if defined?(@message)

    @message = (Message.find_by(id: @delivery.message_id, inbox_id: @delivery.inbox_id) if @delivery.message_id.present?)
  end
end
