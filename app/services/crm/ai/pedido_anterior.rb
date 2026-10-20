# Card que renasce (#1925). O cliente volta depois de um card encerrado (ou um "oi" abre card novo) e a IA de etapa do
# card novo lia só as conversas DELE: a cotação enviada no card anterior, em outra conversa ou antes da janela de
# mensagens recentes, não chegava ao modelo, e o card novo ficava na 1ª etapa.
#
# Aqui sai o pedido anterior: o card ENCERRADO mais recente do mesmo contato, no mesmo funil, que nasceu antes deste.
# Quem decide se é o mesmo pedido retomado ou outro pedido é o modelo (ClassifierPrompt::PEDIDO_ANTERIOR), com a saída
# "não se aplica". O funil é o mesmo para não trazer pedido de outro tipo; aberto fica de fora porque já é outro assunto
# vivo (other_subjects), e arquivado é descarte.
#
#   Crm::Ai::PedidoAnterior.do_card(card)                    # => Crm::Card ou nil
#   Crm::Ai::PedidoAnterior.mensagens(anterior, card, fora:) # => [Message], da mais antiga à mais nova
#   Crm::Ai::PedidoAnterior.payload(anterior)                # => dados do card anterior, sem as mensagens
module Crm::Ai::PedidoAnterior
  # Poucas: é o fim do pedido anterior (a proposta, a recusa), não a conversa inteira. Cada uma ainda passa pelo teto de
  # caracteres do ContextBuilder.
  MAX_MENSAGENS = 8

  module_function

  def do_card(card)
    return if card.contact_id.blank? || card.created_at.blank?

    Crm::Card.where(account_id: card.account_id, contact_id: card.contact_id, pipeline_id: card.pipeline_id,
                    status: Crm::Cards::Outcome::CLOSED_STATUSES)
             .where.not(id: card.id)
             .where(created_at: ...card.created_at)
             .includes(:stage)
             .order(Arel.sql('crm_cards.closed_at DESC NULLS LAST'), id: :desc)
             .first
  end

  # As últimas mensagens da conversa principal do card anterior até o nascimento deste. `fora`: as que já vão em
  # recent_messages (card novo na mesma conversa), para não repetir.
  def mensagens(anterior, card, fora:)
    return [] if anterior.conversation_id.blank?

    Message.where(account_id: anterior.account_id, conversation_id: anterior.conversation_id, private: false)
           .where.not(message_type: :activity)
           .where(created_at: ..card.created_at)
           .where.not(id: fora)
           .includes(:attachments)
           .reorder(id: :desc)
           .limit(MAX_MENSAGENS)
           .to_a.reverse
  end

  def payload(anterior)
    {
      title: anterior.title,
      status: anterior.status,
      stage: anterior.stage&.name,
      closed_at: anterior.closed_at&.iso8601,
      value: (anterior.value_cents.positive? ? { amount_cents: anterior.value_cents, currency: anterior.currency } : nil)
    }.compact
  end
end
