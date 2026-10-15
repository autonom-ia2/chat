# #1590 — por que uma mensagem marcada não saiu, como um código estável que a tela troca por uma frase simples.
# O texto cru de `send_error` continua fora da API (pode trazer detalhe técnico do provedor): só o código sai.
# Os motivos conhecidos são os do SendFailure; qualquer outro vira 'outro'. Recusa do cliente não é
# falha (o lembrete é cancelado, chat#737), mas a tela também precisa dizer por que não saiu.
class Crm::FollowUps::SendErrorCode
  SENDER = Crm::FollowUps::MessageSender
  FAILURE = Crm::FollowUps::SendFailure
  CODES = {
    FAILURE::CONVERSATION_REQUIRED => 'sem_conversa',
    FAILURE::NOT_WHATSAPP_CAPABLE => 'canal',
    FAILURE::SENDER_REQUIRED => 'sem_remetente',
    SENDER::WHATSAPP_API_UNAVAILABLE => 'celular_desconectado',
    FAILURE::TEMPLATE_NAME_REQUIRED => 'sem_modelo',
    FAILURE::API_TEMPLATE_REQUIRED => 'sem_modelo',
    FAILURE::API_TEMPLATE_INVALID => 'modelo_invalido'
  }.freeze
  OTHER = 'outro'.freeze
  OPTED_OUT = 'recusou'.freeze
  FLAG = 'crm_mensagem_marcada'.freeze

  # Sem a flag, a API fica como antes: nem a chave `send_error_code` sai.
  def self.enabled?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def self.for(follow_up)
    metadata = follow_up.metadata.to_h
    return OPTED_OUT if follow_up.canceled? && metadata['canceled_reason'] == SENDER::OPTED_OUT_REASON

    # Só enquanto a falha vale: reagendado (pending de novo) ou enviado depois, o motivo antigo não aparece.
    error = metadata['send_error'].to_s
    return if error.blank? || !follow_up.overdue?

    CODES.fetch(error, OTHER)
  end
end
