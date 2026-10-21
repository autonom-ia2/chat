# Quem falou por último em cada conversa (cliente × nós), agrupado por chave — em geral, o card e as conversas dele.
#
# Por que existe (#1962): quem espera resposta vinha do modelo (last_turn_owner) e só nas avaliações com IA. O
# ScoreDecayJob, que recalcula sem IA, não sabia quem estava esperando e deixava esfriar a dívida nossa. Aqui é
# dado do banco, para o lote inteiro em duas consultas, sem uma por conversa.
#
# "Real" parte do critério de Crm::Conversations::LastRealMessageAt (Message.chat: sem atividade, sem nota privada).
# Do cliente conta o `incoming`. Do nosso lado conta o `outgoing` que é resposta, no mesmo critério do waiting_since
# do próprio Chatwoot (Message#clear_waiting_since_on_outgoing_response e #human_response?):
#   - `template` (saudação, ausência, pedido de e-mail, pesquisa) não é turno de ninguém;
#   - mensagem de regra de automação ou de campanha não responde o cliente;
#   - com a passagem do robô para pessoa pendente (#1377), o robô continua falando, mas o cliente ainda espera o
#     time: ali só conta resposta de pessoa;
#   - mensagem que falhou no envio nunca chegou ao cliente (o mesmo de Crm::Memoria::Origem#foi_ao_cliente?).
#
# A conta é por conversa: o cliente que pergunta no WhatsApp continua esperando mesmo que a gente mande e-mail em
# outra conversa do card. A chave espera quando alguma conversa dela espera, desde a pergunta mais antiga que
# segue sem resposta entre essas conversas. Empate de horário desempata pelo id (ordem de gravação).
class Crm::Conversations::LastTurns
  Turn = Struct.new(:last_message_at, :customer_waiting, :waiting_since, keyword_init: true)
  Last = Struct.new(:at, :id)

  LATEST_SQL = <<~SQL.squish.freeze
    SELECT c.id, (c.additional_attributes ->> '#{ConversationBotHandoff::BOT_HANDOFF_WAITING_SINCE_KEY}') IS NOT NULL AS handoff,
           inc.created_at AS customer_at, inc.id AS customer_id, ours.created_at AS ours_at, ours.id AS ours_id
    FROM conversations c
    LEFT JOIN LATERAL (
      SELECT m.created_at, m.id FROM messages m
      WHERE m.conversation_id = c.id AND m.account_id = c.account_id AND m.message_type = :incoming AND m.private = FALSE
      ORDER BY m.created_at DESC, m.id DESC LIMIT 1
    ) inc ON TRUE
    LEFT JOIN LATERAL (
      SELECT m.created_at, m.id FROM messages m
      WHERE m.conversation_id = c.id AND m.account_id = c.account_id AND m.message_type = :outgoing AND m.private = FALSE
        AND m.status IS DISTINCT FROM :failed
      ORDER BY m.created_at DESC, m.id DESC LIMIT 1
    ) ours ON TRUE
    WHERE c.id IN (:ids)
  SQL

  # conversation_ids_by_key: { chave => [conversation_id, ...] } → { chave => Turn }
  def self.for(conversation_ids_by_key)
    ids = conversation_ids_by_key.values.flatten.compact.uniq
    per_conversation = ids.empty? ? {} : new(ids).per_conversation

    conversation_ids_by_key.transform_values do |conversation_ids|
      combine(conversation_ids.compact.uniq.filter_map { |id| per_conversation[id] })
    end
  end

  def self.combine(turns)
    waiting = turns.select(&:customer_waiting)
    Turn.new(last_message_at: turns.filter_map(&:last_message_at).max,
             customer_waiting: waiting.any?,
             waiting_since: waiting.filter_map(&:waiting_since).min)
  end
  private_class_method :combine

  def initialize(conversation_ids)
    @conversation_ids = conversation_ids
  end

  # Consulta 1: por conversa, a última entrada do cliente e a última saída nossa que chegou, com acesso indexado
  # (LIMIT 1 por conversa). Consulta 2, só para as conversas em que saímos depois do cliente: essas saídas, para
  # saber se alguma é resposta de verdade.
  def per_conversation
    rows = latest_rows
    replied = replied_conversation_ids(rows.select { |row| row[:ours] && later?(row[:ours], row[:customer]) })

    rows.to_h { |row| [row[:id], conversation_turn(row, replied.include?(row[:id]))] }
  end

  private

  def conversation_turn(row, replied)
    customer = row[:customer]
    waiting = customer.present? && !replied
    Turn.new(last_message_at: [customer&.at, row[:ours]&.at].compact.max, customer_waiting: waiting,
             waiting_since: (customer.at if waiting))
  end

  def latest_rows
    sql = ActiveRecord::Base.sanitize_sql_array(
      [LATEST_SQL, { ids: @conversation_ids, incoming: Message.message_types[:incoming],
                     outgoing: Message.message_types[:outgoing], failed: Message.statuses[:failed] }]
    )
    Conversation.connection.select_all(sql).map do |r|
      { id: r['id'], handoff: ActiveModel::Type::Boolean.new.cast(r['handoff']) == true,
        customer: last(r['customer_at'], r['customer_id']), ours: last(r['ours_at'], r['ours_id']) }
    end
  end

  def last(at, id)
    return if id.nil?

    Last.new(at.is_a?(String) ? Time.find_zone('UTC').parse(at) : at, id.to_i)
  end

  # Sem cliente na conversa, ninguém espera; com cliente, saímos depois dele quando (horário, id) é maior.
  def later?(ours, customer)
    customer.nil? || ([ours.at, ours.id] <=> [customer.at, customer.id]).positive?
  end

  # Carrega só as saídas posteriores à última fala do cliente, nas conversas em que há saída depois dela, e
  # diz em quais alguma delas é resposta. O filtro é em Ruby: content_attributes é JSON gravado como texto.
  def replied_conversation_ids(rows)
    candidates = rows.select { |row| row[:customer] }
    return Set.new if candidates.empty?

    handoff = candidates.select { |row| row[:handoff] }.to_set { |row| row[:id] }
    outgoing_after_customer(candidates).select { |message| reply?(message, handoff.include?(message.conversation_id)) }
                                       .to_set(&:conversation_id)
  end

  def outgoing_after_customer(candidates)
    after = candidates.map do |row|
      ActiveRecord::Base.sanitize_sql_array(['(messages.conversation_id = ? AND (messages.created_at, messages.id) > (?, ?))',
                                             row[:id], row[:customer].at, row[:customer].id])
    end
    Message.unscoped.select(:id, :conversation_id, :sender_type, :content_attributes, :additional_attributes)
           .where(message_type: :outgoing, private: false)
           .where('messages.status IS DISTINCT FROM ?', Message.statuses[:failed])
           .where(after.join(' OR '))
  end

  def reply?(message, handoff)
    return false if message.content_attributes.to_h['automation_rule_id'].present? || campaign?(message)
    return true unless handoff

    message.sender_type == 'User' || message.content_attributes.to_h['external_echo'].present?
  end

  def campaign?(message)
    extra = message.additional_attributes.to_h
    extra['campaign_id'].present? || extra['whatsapp_api_campaign_id'].present?
  end
end
