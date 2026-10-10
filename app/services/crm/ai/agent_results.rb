# O que as ferramentas do agente produziram nas conversas do card (multifunil, #1146): uma frase por execução encerrada,
# escrita pela própria ferramenta (`Native::Base.resumo_para_o_crm`), que decide pelo resultado (uma cotação que
# encerrou como falha mas trouxe preço tem o que dizer). A IA do card lê com as mensagens e preenche os campos que o
# admin criou, para qualquer negócio. Entra o que ENCERROU depois que o card começou: a cotação pedida segundos antes de
# a IA criar o card do assunto é deste card; a de um pedido antigo, encerrada antes, não.
class Crm::Ai::AgentResults
  MAX = 5
  MAX_CARACTERES = 300
  ENCERRADAS = %w[done failed].freeze

  def initialize(card:, conversation_ids:)
    @card = card
    @conversation_ids = conversation_ids
  end

  def perform
    execucoes.filter_map do |run|
      resumo = resumo_de(run)
      next if resumo.blank?

      { tool: run.slug, started_at: run.created_at.iso8601, finished_at: run.updated_at.iso8601, summary: resumo }
    end
  end

  private

  def execucoes
    return [] if @conversation_ids.empty?

    ::Autonomia::Agents::ToolRun.where(account_id: @card.account_id, conversation_id: @conversation_ids, status: ENCERRADAS)
                                .where(updated_at: @card.created_at..)
                                .order(updated_at: :desc).limit(MAX).to_a.reverse
  end

  def resumo_de(run)
    ::Autonomia::Agents::Tools::Registry.find(run.slug)&.resumo_para_o_crm(run).to_s.squish.first(MAX_CARACTERES).presence
  rescue StandardError => e
    Rails.logger.warn("[CRM AI agent results] run=#{run.id} #{e.class}")
    nil
  end
end
