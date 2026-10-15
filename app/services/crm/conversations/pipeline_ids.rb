# Funis de cada conversa, para o filtro "Funil" da lista conferir em tempo real (multifunil #1150): a conversa nova ou
# atualizada que chega pelo websocket só entra na lista filtrada se for do funil escolhido.
#
# Mesma regra do Crm::Conversations::PipelineFilter e do acesso por funil (Crm::Access::ConversationScope): card aberto
# manda; sem card aberto, valem os ganhos/perdidos; arquivado, resolvido e cancelado não contam. Lista vazia = "Sem
# assunto". Cards principais e vinculados (#1141), numa consulta para cada um, para a página inteira de uma vez.
#
# Só ids, sem nome: quem recebe a conversa já a vê, e o seletor de funis mostra só os nomes dos funis da pessoa.
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
    open, closed = conversation_rows.partition { |(_conversation_id, _pipeline_id, status)| status_value(status) == OPEN }
    (open.presence || closed).map(&:second).uniq.sort
  end

  # pluck devolve o enum como texto ("open") na coluna do modelo e como número na coluna da junção.
  def status_value(status)
    Crm::Card.statuses.fetch(status.to_s, status)
  end

  def rows
    holding = Crm::Card.statuses.values - Crm::Access::ConversationScope::RELEASED
    primary = Crm::Card.where(account_id: account_ids, conversation_id: conversation_ids, status: holding)
                       .pluck(:conversation_id, :pipeline_id, :status)
    linked = Crm::CardConversation.joins(:card)
                                  .where(account_id: account_ids, conversation_id: conversation_ids)
                                  .where(crm_cards: { status: holding, account_id: account_ids })
                                  .pluck('crm_card_conversations.conversation_id', 'crm_cards.pipeline_id', 'crm_cards.status')
    primary + linked
  end

  def conversation_ids
    @conversation_ids ||= @conversations.map(&:id)
  end

  def account_ids
    @account_ids ||= @conversations.map(&:account_id).uniq
  end
end
