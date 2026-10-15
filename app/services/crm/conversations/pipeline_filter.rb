# Filtro "Funil" da lista de conversas (multifunil #1150, decisão do Rodrigo em 12/10). PROTÓTIPO 1150c.
#
# crm_pipeline_id = id do funil: conversas cujo assunto está nesse funil. Mesma regra do acesso por funil
# (Crm::Access::ConversationScope): card aberto manda; sem card aberto, vale o ganho/perdido. Arquivado, resolvido e
# cancelado não contam (soltam a conversa para a triagem).
# crm_pipeline_id = 'none': "Sem assunto", a triagem: nenhum card que prenda a conversa.
#
# Só RESTRINGE a relação que chega (já filtrada por caixa e por acesso por funil). Funil que a pessoa não enxerga
# (Crm::Access::VisiblePipelines) responde lista vazia, sem dizer se o funil existe.
class Crm::Conversations::PipelineFilter
  NONE = 'none'.freeze

  def initialize(user:, account:, value:)
    @user = user
    @account = account
    @value = value.to_s
  end

  def apply(relation)
    return relation if @value.blank?
    return relation.where(sanitize("NOT #{card_exists('', 'NOT IN (:released)')}")) if @value == NONE

    pipeline_id = Integer(@value, exception: false)
    return relation.none unless pipeline_id && visible?(pipeline_id)

    relation.where(sanitize(in_pipeline_sql, pipeline_id: pipeline_id))
  end

  private

  def visible?(pipeline_id)
    @account.crm_pipelines.exists?(id: pipeline_id) &&
      Crm::Access::VisiblePipelines.new(user: @user, account: @account).visible?(pipeline_id)
  end

  def in_pipeline_sql
    in_pipeline = ' AND crm_filter_cards.pipeline_id = :pipeline_id'
    "(#{card_exists(in_pipeline, 'IN (:open)')} OR (NOT #{card_exists('', 'IN (:open)')} " \
      "AND #{card_exists(in_pipeline, 'IN (:closed)')}))"
  end

  # Card principal da conversa ou vínculo em crm_card_conversations (#1141). Dois EXISTS para cada um entrar pelo
  # índice da conversa, como no ConversationScope.
  def card_exists(pipeline_filter, status)
    '(EXISTS (SELECT 1 FROM crm_cards crm_filter_cards WHERE crm_filter_cards.account_id = :account_id ' \
      "AND crm_filter_cards.conversation_id = conversations.id AND crm_filter_cards.status #{status}#{pipeline_filter}) " \
      'OR EXISTS (SELECT 1 FROM crm_card_conversations crm_filter_links INNER JOIN crm_cards crm_filter_cards ' \
      'ON crm_filter_cards.id = crm_filter_links.card_id AND crm_filter_cards.account_id = :account_id ' \
      'WHERE crm_filter_links.account_id = :account_id AND crm_filter_links.conversation_id = conversations.id ' \
      "AND crm_filter_cards.status #{status}#{pipeline_filter}))"
  end

  def sanitize(sql, binds = {})
    scope = Crm::Access::ConversationScope
    ActiveRecord::Base.sanitize_sql_array(
      [sql, { account_id: @account.id, released: scope::RELEASED, open: scope::OPEN, closed: scope::CLOSED }.merge(binds)]
    )
  end
end
