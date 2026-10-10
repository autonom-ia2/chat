# O que as ferramentas do agente produziram nas conversas do card (multifunil, #1146): uma frase por execução terminada,
# escrita pela própria ferramenta (`Native::Base.resumo_para_o_crm`). A IA do card lê com as mensagens e preenche os
# campos que o admin criou, para qualquer negócio. Só o que aconteceu depois que o card começou: o resultado de um
# pedido anterior não vai para o card do pedido de agora.
class Crm::Ai::AgentResults
  MAX = 5

  def initialize(card:)
    @card = card
  end

  def perform
    execucoes.filter_map do |run|
      resumo = resumo_de(run)
      { tool: run.slug, finished_at: run.updated_at.iso8601, summary: resumo } if resumo.present?
    end
  end

  private

  def execucoes
    return [] if conversation_ids.empty?

    ::Autonomia::Agents::ToolRun.where(account_id: @card.account_id, conversation_id: conversation_ids, status: 'done')
                                .where(created_at: @card.created_at..)
                                .order(updated_at: :desc).limit(MAX).to_a.reverse
  end

  def conversation_ids
    @conversation_ids ||= ([@card.conversation_id] + @card.card_conversations.pluck(:conversation_id)).compact.uniq
  end

  def resumo_de(run)
    ::Autonomia::Agents::Tools::Registry.find(run.slug)&.resumo_para_o_crm(run).to_s.squish.first(400).presence
  rescue StandardError => e
    Rails.logger.warn("[CRM AI agent results] run=#{run.id} #{e.class}")
    nil
  end
end
