# UMA MENSAGEM AUTOMÁTICA POR CONVERSA POR VEZ (multifunil 7/11, #1147). Com vários pedidos na mesma conversa, cada card
# pode ter a sua cadência, o seu retorno agendado e o seu envio programado. Sem esta trava, dois saíam juntos para o
# mesmo cliente. O que chega na vez de outro é ADIADO, nunca cancelado: o follow-up continua pendente, com novo horário.
#
# Duas guardas: (1) outro envio automático desta conversa saiu há menos de INTERVALO; (2) outro está saindo agora
# (trava em Redis enquanto o envio roda, que inclui a chamada de IA da composição).
class Crm::FollowUps::ConversationSendGate
  INTERVALO = 10.minutes
  TRAVA = 5.minutes
  ESPERA_TRAVADA = 1.minute
  # Mensagens recentes olhadas atrás de um toque automático. `content_attributes` é json com string dentro
  # (ver CadenceAnchor): o filtro por `crm_follow_up_id` é feito em Ruby, numa janela curta.
  JANELA = 50

  def initialize(follow_up, now: Time.current)
    @follow_up = follow_up
    @now = now
  end

  # Roda o envio se a conversa está livre; senão adia o follow-up e devolve :postponed.
  def perform
    conversation = @follow_up.conversation
    return yield if conversation.blank?

    resultado = nil
    rodou = Redis::LockManager.new.with_lock(chave(conversation), TRAVA.to_i) do
      # Conferido já com a trava: dois follow-ups não passam juntos pela checagem.
      recente = envio_recente(conversation)
      resultado = recente ? adiar(recente.created_at + INTERVALO, 'outro_envio_recente') : yield
      true
    end
    rodou ? resultado : adiar(@now + ESPERA_TRAVADA, 'outro_envio_em_andamento')
  end

  private

  def chave(conversation)
    "crm:follow_up:envio_automatico:conversa:#{conversation.id}"
  end

  # O último toque automático de OUTRO follow-up nesta conversa, se saiu há menos de INTERVALO.
  def envio_recente(conversation)
    conversation.messages.outgoing.where(created_at: (@now - INTERVALO)..).reorder(id: :desc).limit(JANELA).find do |message|
      id = message.content_attributes.to_h['crm_follow_up_id']
      id.present? && id.to_i != @follow_up.id
    end
  end

  def adiar(quando, motivo)
    @follow_up.update!(due_at: quando)
    Rails.logger.info("[crm][follow_ups][gate] follow_up_id=#{@follow_up.id} adiado motivo=#{motivo} para=#{quando.iso8601}")
    :postponed
  end
end
