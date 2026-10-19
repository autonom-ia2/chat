# A coluna em que nasce o card do pedido novo (#1910, flag `crm_assunto_na_etapa`). O modelo maior (Reviewer), que já
# dá o nome ao pedido, escolhe também a etapa pela frase de cada uma (ai_criteria), ou "nenhuma etapa clara": aí o card
# nasce na 1ª etapa, como antes. Quem decide é o modelo; aqui só se diz quais etapas podem receber card novo.
#
# Candidatas: etapas com frase, nunca de ganho, perda ou resolvido. No funil de Vender, só as de categoria novo ou
# andamento (decisão do Rodrigo, 19/10): uma venda não nasce na negociação. Vale só na caixa em Automática; no Sugerir o
# card aceito nasce na 1ª etapa, como antes.
#
# Card que nasce (ou é levado) numa etapa que não é a 1ª roda as automações de ENTRADA dela, como rodariam quando a IA
# de movimento o levasse para lá minutos depois. As de saída da 1ª não rodam: o card nunca esteve nela.
module Crm::Subjects::Etapa
  FLAG = 'crm_assunto_na_etapa'.freeze
  NENHUMA = 'nenhuma_etapa_clara'.freeze
  CATEGORIAS_DE_VENDER = %w[novo andamento].freeze
  CATEGORIA_DE_FECHAMENTO = 'resolvido'.freeze
  ORIGEM = 'crm_subjects'.freeze

  module_function

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def chave(stage)
    "etapa_#{stage.id}"
  end

  def primeira(pipeline)
    pipeline.stages.order(:position, :id).first
  end

  def candidatas(pipeline)
    pipeline.stages.order(:position, :id).select { |stage| candidata?(pipeline, stage) }
  end

  # As automações de entrada da etapa, quando não é a 1ª. Chamado fora da trava da conversa. O card já está gravado:
  # uma falha aqui vai para o rastreador e não desfaz a decisão (desfazer faria o retry criar o card de novo).
  def entrar(card, etapa)
    return if etapa.nil? || etapa.id == primeira(card.pipeline)&.id

    Crm::StageAutomations::Runner.new(card: card, actor: nil, from_stage_id: nil, to_stage_id: etapa.id,
                                      automation_context: { source: ORIGEM }).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("[crm][assunto] automação de entrada falhou card=#{card.id} etapa=#{etapa.id} erro=#{e.class}")
  end

  def candidata?(pipeline, stage)
    return false if stage.is_won_stage || stage.is_lost_stage || Crm::Ai::Config.stage_ai_criteria(stage).blank?

    categoria = stage.metadata.to_h['category']
    return CATEGORIAS_DE_VENDER.include?(categoria) if pipeline.kind == 'sell'

    categoria != CATEGORIA_DE_FECHAMENTO
  end
end
