# Última mensagem real de cada lado (cliente × nós), agrupada por chave — em geral, o card e as conversas dele.
#
# Por que existe (#1962): quem espera resposta vinha do modelo (last_turn_owner) e só nas avaliações com IA. O
# ScoreDecayJob, que recalcula sem IA, não sabia quem estava esperando e deixava esfriar a dívida nossa. Aqui é
# dado do banco, para o lote inteiro em duas consultas agregadas, sem uma por conversa.
#
# "Real" parte do critério de Crm::Conversations::LastRealMessageAt (Message.chat: sem atividade, sem nota
# privada) e só conta turno de verdade: do cliente, `incoming`; nosso, `outgoing` (pessoa, robô, automação).
# Fica de fora o `template` — mensagem automática do Chatwoot (saudação, ausência, pedido de e-mail, pesquisa) —,
# que não responde ninguém; o waiting_since do próprio Chatwoot também não a trata como resposta.
class Crm::Conversations::LastTurns
  Turn = Struct.new(:last_message_at, :customer_waiting, keyword_init: true)

  # conversation_ids_by_key: { chave => [conversation_id, ...] } → { chave => Turn }
  def self.for(conversation_ids_by_key)
    ids = conversation_ids_by_key.values.flatten.compact.uniq
    customer = ids.empty? ? {} : latest_by_conversation(ids, :incoming)
    ours = ids.empty? ? {} : latest_by_conversation(ids, :outgoing)

    conversation_ids_by_key.transform_values do |conversation_ids|
      turn(conversation_ids.compact.filter_map { |id| customer[id] }.max,
           conversation_ids.compact.filter_map { |id| ours[id] }.max)
    end
  end

  # `reorder(nil)` derruba o `default_scope { order(created_at: :asc) }` do Message: sem isso o ORDER BY
  # sobra na consulta agregada e o Postgres recusa o GROUP BY (PG::GroupingError, produção 21/09).
  def self.latest_by_conversation(ids, message_type)
    Message.chat.where(conversation_id: ids, message_type: message_type).reorder(nil)
           .group(:conversation_id).maximum(:created_at)
  end

  def self.turn(customer_at, ours_at)
    Turn.new(
      last_message_at: [customer_at, ours_at].compact.max,
      customer_waiting: customer_at.present? && (ours_at.blank? || customer_at > ours_at)
    )
  end

  private_class_method :latest_by_conversation, :turn
end
