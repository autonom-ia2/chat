# QUANDO UM HUMANO DEVOLVEU A CONVERSA À IA, depois de uma passagem (chat#632, 23/09/2026).
#
# A passagem à equipe relia a conversa inteira a cada evento, e a fala antiga do agente ("vou encaminhar para alguém da
# equipe") continuava lá: o operador desatribuía para devolver à IA e, no evento seguinte (a própria desatribuição
# dispara a avaliação), a IA do CRM decidia "transferir" de novo e reatribuía. Na conta 16, seis devoluções seguidas em
# 27 minutos voltaram para o mesmo atendente em até 34 segundos.
#
# O INSTANTE É GRAVADO NA HORA DA DEVOLUÇÃO (`registrar!`, chamado pelo listener de `assignee_changed` antes de a
# avaliação ser enfileirada), e não inferido das atividades da conversa: toda atividade (resolver, etiqueta, SLA,
# reabertura) conta como "atividade", e elas nascem assíncronas, depois da mensagem que as provocou (revisão da #633).
# Só vale para a passagem direta: no convite a conversa nunca foi de ninguém, então não há o que devolver.
module Crm::Ai::DevolucaoAIa
  CHAVE = 'returned_to_ai_at'.freeze
  # A conversa devolvida: o carimbo é do card, e um card pode ter várias conversas (revisão da #633).
  CONVERSA = 'returned_conversation_id'.freeze
  # Quantas mensagens depois da devolução olhar procurando um pedido novo: passando disso, com certeza há um.
  LIMITE = 50

  module_function

  # A conversa acabou de ficar sem responsável: carimba a devolução nos cards que a tinham passado à equipe.
  def registrar!(conversation, momento)
    return if conversation.assignee_id.present?

    # Pelo vínculo e pela conversa primária: card antigo pode ter a conversa só em `crm_cards.conversation_id`.
    Crm::Card.where(account_id: conversation.account_id).left_joins(:card_conversations)
             .where('crm_card_conversations.conversation_id = :id OR crm_cards.conversation_id = :id', id: conversation.id)
             .distinct.find_each { |card| carimbar!(card, conversation, momento) }
  end

  # -> o instante em que a conversa voltou para a IA, ou nil (sem devolução depois da última passagem direta).
  def em(card, conversation)
    ai = ai_de(card)
    return unless devolvida_esta?(ai, conversation)

    devolvida = instante(ai[CHAVE])
    passagem = instante(ai['last_handoff_at'])
    devolvida if devolvida && passagem && devolvida >= passagem
  end

  # -> o carimbo pode valer para esta conversa: ela está sem responsável, a passagem foi direta e foi ela a devolvida.
  def devolvida_esta?(meta, conversation)
    return false if conversation.blank? || conversation.assignee_id.present?
    return false if meta['last_handoff_mode'] == 'invite'

    meta[CONVERSA].blank? || meta[CONVERSA].to_i == conversation.id
  end

  # -> devolvida e, desde então, nem o cliente nem o agente de IA escreveram nada?
  def sem_pedido_novo?(card, conversation)
    devolvida = em(card, conversation)
    return false if devolvida.blank?

    conversation.messages.chat.where('created_at > ?', devolvida).reorder(id: :desc).limit(LIMITE).none? { |m| pedido?(m) }
  end

  # Quem pode pedir a passagem: o cliente, ou o agente de IA que declara que vai encaminhar. A fala do próprio
  # atendente ("a Lia segue com você") e o toque automático do CRM (que sai como User) não são pedido.
  def pedido?(message)
    message.incoming? || message.sender_type == 'AgentBot'
  end

  def carimbar!(card, conversation, momento)
    ai = ai_de(card)
    return if ai['last_handoff_at'].blank? || ai['last_handoff_mode'] == 'invite'

    card.update!(metadata: (card.metadata || {}).deep_merge('ai' => { CHAVE => momento.iso8601, CONVERSA => conversation.id }))
  end

  def ai_de(card)
    (card.metadata || {}).fetch('ai', {}).to_h
  end

  def instante(valor)
    valor.present? ? Time.zone.parse(valor.to_s) : nil
  rescue ArgumentError
    nil
  end
end
