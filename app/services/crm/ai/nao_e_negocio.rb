# "NÃO É NEGÓCIO" (#1922). A IA de etapa só sabia mover entre etapas: o card que não é pedido de cliente (alguém
# oferecendo serviço, mensagem por engano, só um link, conversa só de robôs, card repetido) ficava parado ou ia para a
# etapa de perda, e inflava a perda. Agora o modelo pode dizer, no campo `nao_e_negocio` da mesma avaliação (nenhuma
# chamada nova), que o card não é negócio; quem decide é ele, com a saída "null" para tudo que não é isso.
#
# Com confiança alta (a mesma do movimento automático) o card é arquivado: sai do quadro, não conta como perda nem como
# venda, para os retornos automáticos e não manda evento de perda aos anúncios. Fica na linha do tempo como "arquivado
# pela IA"; desfazer é reabrir o card (Resultado "Arquivado" na lista), como qualquer card arquivado.
#
# A IA nunca tira do funil o card que uma pessoa já disse que vale: criado ou reaberto por uma pessoa, ou com valor. Card
# repetido sai só o mais novo (o mais antigo aberto da conversa fica). O resto das guardas (movimento automático ligado
# no funil, etapa mexida por uma pessoa há pouco, "Avaliar agora") é do Crm::Ai::Evaluator.
class Crm::Ai::NaoENegocio
  MOTIVOS = %w[fora_do_negocio duplicado].freeze
  DECISOES_DA_PESSOA = %w[create reopen].freeze

  def initialize(card:, decisao:)
    @card = card
    @decisao = decisao.is_a?(Hash) ? decisao.with_indifferent_access : {}
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
    MOTIVOS.include?(motivo) && confianca >= Crm::Ai::Config::AUTO_MOVE_THRESHOLD
  end

  # Relido sob o lock: uma pessoa pode ter fechado ou mexido no card enquanto o modelo pensava.
  def pode_arquivar?
    return false unless @card.open?
    return false if @card.value_cents.to_i.positive? || pessoa_decidiu?

    motivo != 'duplicado' || card_mais_antigo_aberto?
  end

  def pessoa_decidiu?
    Crm::Activity.exists?(account_id: @card.account_id, card_id: @card.id, actor_type: 'user', event_type: DECISOES_DA_PESSOA)
  end

  # O repetido é o mais novo: outro card aberto, mais antigo, nas conversas deste.
  def card_mais_antigo_aberto?
    conversas = [@card.conversation_id, *@card.card_conversations.pluck(:conversation_id)].compact.uniq
    return false if conversas.empty?

    abertos = @card.account.crm_cards.open
    vinculados = Crm::CardConversation.where(account_id: @card.account_id, conversation_id: conversas).select(:card_id)
    abertos.where(conversation_id: conversas).or(abertos.where(id: vinculados)).exists?(id: ...@card.id)
  end

  def arquivar!
    @card.update!(status: :archived, last_activity_at: Time.current)
    @card.account.crm_ai_stage_suggestions.where(card: @card, status: :pending).find_each { |sugestao| sugestao.update!(status: :expired) }
    Crm::ActivityLogger.new(card: @card, actor: nil, event_type: 'archive', payload: payload).perform
    true
  end

  def payload
    { by: 'ai', motivo: motivo, confidence: confianca, reasoning: @decisao[:reasoning].to_s.truncate(300) }
  end
end
