# "NÃO É NEGÓCIO" (#1922). A IA de etapa só sabia mover entre etapas: o card que não é pedido de cliente (alguém
# oferecendo serviço, mensagem por engano, conversa só de robôs, card repetido) ficava parado ou ia para a etapa de
# perda, e inflava a perda. Agora o modelo pode dizer, no campo `nao_e_negocio` da mesma avaliação (nenhuma chamada
# nova), que o card não é negócio; quem decide é ele, com a saída "null" para tudo que não é isso.
#
# Com confiança alta (a mesma do movimento automático) o card é arquivado: sai do quadro, não conta como perda nem como
# venda, para os retornos automáticos e não manda evento de perda aos anúncios. Fica na linha do tempo como "arquivado
# pela IA"; desfazer é reabrir o card (Resultado "Arquivado" na lista), como qualquer card arquivado.
#
# Guardas de código (estruturais; o texto da conversa é só do modelo), relidas sob o lock do card:
# - uma pessoa já mexeu no card, em qualquer tempo (criou, moveu, reabriu, editou, anotou: qualquer atividade dela na
#   linha do tempo, ou uma tarefa criada por ela), ou ele tem valor: fica;
# - chegou mensagem do cliente depois que a conversa foi lida para esta avaliação: a decisão é velha, fica (a próxima
#   avaliação lê a mensagem nova);
# - repetido: o modelo diz QUAL card fica (`duplicado_de`), e ele precisa estar aberto, ser mais antigo, ser do mesmo
#   funil e estar nas conversas deste. Sem isso, nada sai.
# O resto (movimento automático ligado no funil, etapa mexida por uma pessoa há pouco, "Avaliar agora") é do
# Crm::Ai::Evaluator.
class Crm::Ai::NaoENegocio
  MOTIVOS = %w[fora_do_negocio duplicado].freeze

  # lido_em: quando a conversa foi lida para a avaliação (Crm::Ai::Evaluator#stage_classifier).
  def initialize(card:, decisao:, lido_em:)
    @card = card
    @decisao = decisao.is_a?(Hash) ? decisao.with_indifferent_access : {}
    @lido_em = lido_em
  end

  # true quando o card foi arquivado.
  def aplicar!
    return false unless decisao_valida?

    arquivado = @card.with_lock { pode_arquivar? && arquivar! }
    Crm::Cards::Broadcaster.broadcast(@card, Events::Types::CRM_CARD_ARCHIVED) if arquivado
    arquivado
  end

  private

  def motivo = @decisao[:motivo].to_s

  def confianca = @decisao[:confidence].to_f

  def decisao_valida?
    MOTIVOS.include?(motivo) && confianca >= Crm::Ai::Config::AUTO_MOVE_THRESHOLD && @lido_em.present?
  end

  def pode_arquivar?
    return false unless @card.open?
    return false if @card.value_cents.to_i.positive? || pessoa_mexeu? || mensagem_nova?

    motivo != 'duplicado' || card_que_fica?
  end

  def pessoa_mexeu?
    Crm::Activity.exists?(account_id: @card.account_id, card_id: @card.id, actor_type: 'user') ||
      @card.follow_ups.where.not(created_by_id: nil).exists?
  end

  def mensagem_nova?
    Message.where(account_id: @card.account_id, conversation_id: conversas, message_type: :incoming)
           .exists?(['created_at > ?', @lido_em])
  end

  def conversas
    @conversas ||= [@card.conversation_id, *@card.card_conversations.pluck(:conversation_id)].compact.uniq
  end

  # O card que fica, apontado pelo modelo: aberto, mais antigo, do mesmo funil e nas conversas deste.
  def card_que_fica?
    id = @decisao[:duplicado_de].to_i
    return false unless id.positive? && id < @card.id && conversas.any?

    abertos = @card.account.crm_cards.open.where(pipeline_id: @card.pipeline_id)
    vinculados = Crm::CardConversation.where(account_id: @card.account_id, conversation_id: conversas).select(:card_id)
    abertos.where(conversation_id: conversas).or(abertos.where(id: vinculados)).exists?(id: id)
  end

  def arquivar!
    @card.update!(status: :archived, last_activity_at: Time.current)
    @card.account.crm_ai_stage_suggestions.where(card: @card, status: :pending).find_each { |sugestao| sugestao.update!(status: :expired) }
    Crm::ActivityLogger.new(card: @card, actor: nil, event_type: 'archive', payload: payload).perform
    true
  end

  def payload
    { by: 'ai', motivo: motivo, duplicado_de: @decisao[:duplicado_de], confidence: confianca,
      reasoning: @decisao[:reasoning].to_s.truncate(300) }.compact
  end
end
