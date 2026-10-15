# Funis de cada conversa (crm_pipeline_ids na resposta da API), para o filtro "Funil" da lista conferir no painel a
# conversa que chega ou muda (multifunil #1150). Vai só na API, que responde a quem já pode ver a conversa; o payload do
# websocket não leva, porque também chega ao contato pelo widget.
#
# Mesma regra do Crm::Conversations::PipelineFilter e do acesso por funil (Crm::Access::ConversationScope): card aberto
# manda; sem card aberto, valem os ganhos/perdidos; arquivado, resolvido e cancelado não contam. Lista vazia = "Sem
# assunto". Cards principais e vinculados (#1141), numa consulta para cada um, para a página inteira de uma vez. O card
# conta só na conta da própria conversa.
class Crm::Conversations::PipelineIds
  OPEN = Crm::Card.statuses[:open]

  def self.for(conversations)
    new(conversations).perform
  end

  def initialize(conversations)
    @conversations = Array(conversations).compact
  end

  # { conversation_id => [pipeline_id, ...] }, com toda conversa pedida presente (lista vazia quando sem assunto).
  def perform
    return {} if @conversations.empty?

    grouped = rows.group_by(&:first)
    @conversations.to_h do |conversation|
      [conversation.id, pipelines_for(grouped.fetch(conversation.id, []))]
    end
  end

  private

  def pipelines_for(conversation_rows)
    open, closed = conversation_rows.partition { |(_conversation_id, _pipeline_id, status)| status == OPEN }
    (open.presence || closed).map(&:second).uniq.sort
  end

  def rows
    primary = Crm::Card.joins(:primary_conversation)
                       .where(conversation_id: conversation_ids, status: holding)
                       .where('crm_cards.account_id = conversations.account_id')
                       .pluck(*columns('crm_cards.conversation_id'))
    linked = Crm::CardConversation.joins(:card, :conversation)
                                  .where(conversation_id: conversation_ids, crm_cards: { status: holding })
                                  .where('crm_cards.account_id = conversations.account_id')
                                  .where('crm_card_conversations.account_id = conversations.account_id')
                                  .pluck(*columns('crm_card_conversations.conversation_id'))
    primary + linked
  end

  # O apelido do status evita o enum do modelo: volta número nas duas consultas.
  def columns(conversation_column)
    [conversation_column, 'crm_cards.pipeline_id', 'crm_cards.status AS crm_card_status'].map { |column| Arel.sql(column) }
  end

  def holding
    Crm::Card.statuses.values - Crm::Access::ConversationScope::RELEASED
  end

  def conversation_ids
    @conversation_ids ||= @conversations.map(&:id)
  end
end
