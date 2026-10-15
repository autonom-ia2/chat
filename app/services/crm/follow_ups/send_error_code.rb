# #1590 — por que uma mensagem marcada não saiu, como um código estável que a tela troca por uma frase simples.
# O texto cru de `send_error` continua fora da API (pode trazer detalhe técnico do provedor): só o código sai.
# Os motivos conhecidos vêm do MessageSender; qualquer outro vira 'outro'. Recusa do cliente não é falha (o lembrete
# é cancelado, chat#737), mas a tela também precisa dizer por que não saiu.
class Crm::FollowUps::SendErrorCode
  CODES = {
    'conversation_required' => 'sem_conversa',
    'not_whatsapp_capable' => 'canal',
    'sender_required' => 'sem_remetente',
    Crm::FollowUps::MessageSender::WHATSAPP_API_UNAVAILABLE => 'celular_desconectado',
    'template_name_required' => 'sem_modelo',
    'whatsapp_api_message_template_id is required outside the messaging window' => 'sem_modelo',
    'whatsapp_api_message_template is invalid for this conversation inbox' => 'modelo_invalido'
  }.freeze
  OTHER = 'outro'.freeze
  OPTED_OUT = 'recusou'.freeze

  def self.for(follow_up)
    metadata = follow_up.metadata.to_h
    return OPTED_OUT if follow_up.canceled? && metadata['canceled_reason'] == Crm::FollowUps::MessageSender::OPTED_OUT_REASON

    # Só enquanto a falha vale: reagendado (pending de novo) ou enviado depois, o motivo antigo não aparece.
    error = metadata['send_error'].to_s
    return if error.blank? || !follow_up.overdue?

    CODES.fetch(error, OTHER)
  end
end
