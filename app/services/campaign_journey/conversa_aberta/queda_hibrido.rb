# A queda da conversa aberta quando o WhatsApp Híbrido assumiu o texto recusado no 131047 (#1453). O reenvio do Híbrido é
# síncrono (WhatsappHybrid::CloudFailureFallback roda o WebTransport dentro do aviso), então, no `ensure` da Queda, o
# resultado já está gravado na Message, sob trava, por outra instância dela: aqui ela é sempre relida do banco pelo
# message_id da entrega. Decide pelo resultado do WebTransport (whatsapp_transport_outcome, #1349):
# - sem a marca do Híbrido: o modelo;
# - `failed` (nada saiu): o modelo;
# - `throttled` (o Híbrido tenta de novo a cada 15 s, com teto): o ConferenciaHibridoJob relê depois; na leitura que
#   passa do teto do Híbrido, se ainda estiver `throttled` DENTRO da trava, fecha como falha e manda o modelo;
# - `accepted` (saiu) ou `uncertain` (pode ter saído): nunca o modelo (seria mensagem dupla); vai ao log;
# - `pending` ou sem resultado com a marca: o Híbrido ainda está enviando (ou parou no meio); nunca o modelo agora.
#   A conferência relê; na leitura tardia, se ainda estiver assim DENTRO da trava, fecha: sem o envio marcado
#   (whatsapp_transport = web) é `failed` e o modelo sai; com ele, `uncertain`.
# O modelo sai pelo QuedaJob: uma vez só (fell_back_at, sob trava) e com as mesmas travas do disparo.
class CampaignJourney::ConversaAberta::QuedaHibrido
  FALLBACK_KEY = 'whatsapp_transport_fallback'.freeze

  # A campanha já mandou o modelo para o texto desta mensagem (o plano B não assume mais o texto).
  def self.template_sent?(message)
    CampaignFreeTextDelivery.where(message_id: message.id, inbox_id: message.inbox_id).where.not(fell_back_at: nil).exists?
  end

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
    when :conferir, :sem_resultado then conferir_depois(tentativa)
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
    return fechar(%w[throttled], tentativa) if outcome == 'throttled' && tentativa >= job::FECHA_THROTTLED
    return fechar([nil, 'pending'], tentativa) if tentativa >= job::ESPERAS.size

    job.set(wait: job::ESPERAS[tentativa]).perform_later(@delivery.id, tentativa + 1)
  end

  # Fecha sob trava (WhatsappHybrid::UnexpectedErrorOutcome) só se o resultado ainda for um dos `estados`; se outro
  # processo o mudou nesse meio tempo (a nova tentativa assumiu, o motor respondeu), nada é gravado. Em qualquer caso,
  # decide de novo pelo que está no banco agora: nunca manda o modelo por uma leitura velha.
  def fechar(estados, tentativa)
    final = WhatsappHybrid::UnexpectedErrorOutcome.settle!(message, only_from: estados, external_error: erro_ao_fechar)
    registrar(:warn, "conferência #{tentativa}: fechar #{estados.compact.join('/')}, no banco: #{final || 'ausente'}")
    reler_e_seguir(tentativa)
  end

  def erro_ao_fechar
    outcome == 'throttled' ? WhatsappHybrid::WebTransport::THROTTLED_OUT_ERROR : WhatsappHybrid::WebTransport::NO_ANSWER_ERROR
  end

  def reler_e_seguir(tentativa)
    remove_instance_variable(:@message) if defined?(@message)
    @attributes = nil
    seguir(tentativa)
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
