# Card que renasce (#1925). O cliente volta depois de um card encerrado (ou um "oi" abre card novo) e a IA de etapa do
# card novo lia só as conversas DELE: a cotação enviada no card anterior, em outra conversa ou antes da janela de
# mensagens recentes, não chegava ao modelo, e o card novo ficava na 1ª etapa.
#
# Aqui sai o pedido anterior: o card mais recente do mesmo contato, no mesmo funil, ENCERRADO antes de este nascer, e só
# quando ele não deu certo (lost/cancelled). Quem decide se é o mesmo pedido retomado ou outro pedido é o modelo
# (ClassifierPrompt::PEDIDO_ANTERIOR), com a saída "não se aplica".
# - Encerrado ANTES do nascimento: um card irmão ainda aberto quando este nasceu é outro assunto vivo, não um anterior.
# - Deu certo (won/resolved): a venda já contou; quem volta é pós-venda ou compra nova, e herdar etapa ou valor contaria a
#   mesma venda duas vezes. Se o último encerrado deu certo, não há pedido anterior a retomar.
# - Mesmo funil: para não trazer pedido de outro tipo. Aberto fica de fora (other_subjects); arquivado é descarte.
#
#   Crm::Ai::PedidoAnterior.do_card(card)              # => Crm::Card ou nil
#   Crm::Ai::PedidoAnterior.mensagens(anterior, fora:) # => [Message], da mais antiga à mais nova
#   Crm::Ai::PedidoAnterior.payload(anterior)          # => dados do card anterior, sem as mensagens
module Crm::Ai::PedidoAnterior
  # Poucas: é o fim do pedido anterior (a proposta, a recusa), não a conversa inteira. Cada uma ainda passa pelo teto de
  # caracteres do ContextBuilder.
  MAX_MENSAGENS = 8

  module_function

  def do_card(card)
    return if card.contact_id.blank? || card.created_at.blank?

    ultimo = Crm::Card.where(account_id: card.account_id, contact_id: card.contact_id, pipeline_id: card.pipeline_id,
                             status: Crm::Cards::Outcome::CLOSED_STATUSES, closed_at: ...card.created_at)
                      .where.not(id: card.id)
                      .includes(:stage)
                      .order(closed_at: :desc, id: :desc)
                      .first
    ultimo if ultimo && Crm::Cards::Outcome::GROUPS[ultimo.status] == 'failure'
  end

  # As últimas mensagens da VIDA do card anterior, na conversa principal e nas vinculadas: do fim do pedido que o contato
  # encerrou antes dele (o que veio antes é de outro assunto) até o encerramento dele (o que veio depois já é a volta, e
  # chega pelo card novo). `fora`: as que já vão em recent_messages (card novo na mesma conversa), para não repetir.
  def mensagens(anterior, fora:)
    conversas = ([anterior.conversation_id] + anterior.card_conversations.pluck(:conversation_id)).compact.uniq
    return [] if conversas.empty?

    Message.where(account_id: anterior.account_id, conversation_id: conversas, private: false)
           .where.not(message_type: :activity)
           .where(created_at: inicio_da_vida(anterior)..anterior.closed_at)
           .where.not(id: fora)
           .includes(:attachments)
           .reorder(id: :desc)
           .limit(MAX_MENSAGENS)
           .to_a.reverse
  end

  # O pedido anterior começa quando o contato encerrou o pedido de antes dele (qualquer funil); sem nenhum, desde o começo.
  # Não é o nascimento do card: ele nasce depois da mensagem que o abriu, e essa mensagem é o pedido.
  def inicio_da_vida(anterior)
    Crm::Card.where(account_id: anterior.account_id, contact_id: anterior.contact_id, closed_at: ...anterior.created_at)
             .where.not(id: anterior.id)
             .maximum(:closed_at)
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
