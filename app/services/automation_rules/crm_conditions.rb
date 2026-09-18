# Condições de Automação sobre o card do CRM da conversa (funil, etapa e status). O card é o mesmo
# que Crm::Cards::ConversationCardFinder escolhe: não arquivado, o principal da conversa primeiro,
# depois o vinculado de menor id. Sem card, "diferente de" é verdadeiro e "igual a" é falso.
module AutomationRules::CrmConditions
  OPERATORS = {
    'crm_pipeline_id' => %w[equal_to not_equal_to is_present is_not_present],
    'crm_stage_id' => %w[equal_to not_equal_to],
    'crm_card_status' => %w[equal_to not_equal_to]
  }.freeze

  COLUMNS = { 'crm_pipeline_id' => 'pipeline_id', 'crm_stage_id' => 'stage_id', 'crm_card_status' => 'status' }.freeze

  JOIN_SQL = <<~SQL.squish.freeze
    LEFT JOIN LATERAL (
      SELECT crm_cards.id, crm_cards.pipeline_id, crm_cards.stage_id, crm_cards.status
      FROM crm_cards
      WHERE crm_cards.account_id = conversations.account_id
        AND crm_cards.status <> #{Crm::Card.statuses[:archived]}
        AND (crm_cards.conversation_id = conversations.id
             OR EXISTS (SELECT 1 FROM crm_card_conversations
                        WHERE crm_card_conversations.card_id = crm_cards.id
                          AND crm_card_conversations.conversation_id = conversations.id))
      ORDER BY (crm_cards.conversation_id = conversations.id) DESC, crm_cards.id
      LIMIT 1
    ) crm_card ON TRUE
  SQL

  def self.key?(attribute_key)
    OPERATORS.key?(attribute_key)
  end

  def self.valid_operator?(condition)
    OPERATORS.fetch(condition['attribute_key'], []).include?(condition['filter_operator'])
  end

  private

  def crm_conditions?
    @rule.conditions.any? { |condition| AutomationRules::CrmConditions.key?(condition['attribute_key']) }
  end

  # Acrescenta a condição de CRM à query e devolve true; false quando a chave não é de CRM.
  def apply_crm_filter(query_hash, current_index)
    return false unless AutomationRules::CrmConditions.key?(query_hash['attribute_key'])

    @query_string += crm_condition_query(query_hash.with_indifferent_access, current_index)
    true
  end

  def crm_condition_query(query_hash, current_index)
    column = "crm_card.#{COLUMNS.fetch(query_hash['attribute_key'])}"
    query_operator = query_hash['query_operator']

    case query_hash['filter_operator']
    when 'is_present' then " crm_card.id IS NOT NULL #{query_operator} "
    when 'is_not_present' then " crm_card.id IS NULL #{query_operator} "
    else crm_equality_query(column, query_hash, current_index)
    end
  end

  def crm_equality_query(column, query_hash, current_index)
    values = crm_condition_values(query_hash)
    query_operator = query_hash['query_operator']
    negated = query_hash['filter_operator'] == 'not_equal_to'
    return " #{negated ? '1=1' : '1=0'} #{query_operator} " if values.blank?

    placeholder = "value_#{current_index}"
    @filter_values[placeholder] = values
    return " (#{column} IS NULL OR #{column} NOT IN (:#{placeholder})) #{query_operator} " if negated

    " #{column} IN (:#{placeholder}) #{query_operator} "
  end

  def crm_condition_values(query_hash)
    values = Array(query_hash['values']).compact_blank
    return Crm::Card.statuses.values_at(*values.map(&:to_s)).compact if query_hash['attribute_key'] == 'crm_card_status'

    values.map(&:to_i)
  end
end
