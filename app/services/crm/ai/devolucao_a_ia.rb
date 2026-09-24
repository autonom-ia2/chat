# QUANDO UM HUMANO DEVOLVEU A CONVERSA À IA, depois de uma passagem (chat#612, 23/09/2026).
#
# A passagem à equipe relia a conversa inteira a cada evento, e a fala antiga do agente ("vou encaminhar para alguém da
# equipe") continuava lá: o operador desatribuía para devolver à IA e, no evento seguinte (a própria desatribuição
# dispara a avaliação), a IA do CRM decidia "transferir" de novo e reatribuía. Na conta 16, seis devoluções seguidas em
# 27 minutos voltaram para o mesmo atendente em até 34 segundos. Uma conversa que ia para a equipe nunca mais voltava
# para a Lia.
#
# O instante da devolução é o da última atividade da conversa depois da passagem (o "desatribuída" que o painel
# registra); sem atividade nenhuma, vale o instante da passagem. Só existe devolução com passagem anterior e com a
# conversa, agora, sem responsável.
module Crm::Ai::DevolucaoAIa
  module_function

  # -> Time do momento em que a conversa voltou para a IA, ou nil.
  def em(card, conversation)
    return if conversation.blank? || conversation.assignee_id.present?

    passagem = ultima_passagem(card)
    return if passagem.blank?

    conversation.messages.where(message_type: :activity).where('created_at > ?', passagem).maximum(:created_at) || passagem
  end

  # -> a conversa foi devolvida e ninguém escreveu nada (cliente ou agente) desde a devolução?
  def sem_mensagem_nova?(card, conversation)
    devolvida = em(card, conversation)
    return false if devolvida.blank?

    conversation.messages.chat.where('created_at > ?', devolvida).none?
  end

  def ultima_passagem(card)
    valor = (card.metadata || {}).dig('ai', 'last_handoff_at')
    valor.present? ? Time.zone.parse(valor.to_s) : nil
  rescue ArgumentError
    nil
  end
end
