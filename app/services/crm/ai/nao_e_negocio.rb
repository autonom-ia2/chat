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
#
# Flag da conta `crm_ia_arquiva_lixo`: sem ela, a regra não vai ao prompt, o campo não vai ao schema, o `id` não vai em
# other_subjects e nada é arquivado (tudo como antes do #1922).
class Crm::Ai::NaoENegocio
  FLAG = 'crm_ia_arquiva_lixo'.freeze
  FORA_DO_NEGOCIO = 'fora_do_negocio'.freeze
  MOTIVOS = [FORA_DO_NEGOCIO, 'duplicado'].freeze
  # IA entende a conversa F3, regra k: "era teste" vira SUGESTÃO de arquivar como não é negócio (#sugerir_teste!), sem
  # contar como perda; a pessoa aceita num clique. Só com a flag `crm_ia_fecha_card` (Crm::Ai::FecharCard::TESTE); as
  # guardas do arquivamento são as mesmas.
  MOTIVO_TESTE = 'teste'.freeze
  # #2395: por quanto tempo o "fora_do_negocio" da IA segura a recriação do card da conversa (decisão do Rodrigo, 30/10).
  BLOQUEIO_DA_RECRIACAO = 30.days

  # O campo da avaliação de etapa (a regra está em ClassifierPrompt::NAO_E_NEGOCIO).
  CAMPO = {
    type: %w[object null],
    description: 'Preencha SOMENTE quando este card não é pedido de cliente (NÃO É NEGÓCIO). null caso contrário.',
    properties: {
      motivo: { type: 'string', enum: MOTIVOS },
      confidence: { type: 'number', minimum: 0, maximum: 1 },
      reasoning: { type: 'string', maxLength: 300, description: 'O fato da conversa que mostra que não é negócio.' },
      duplicado_de: { type: %w[integer null], description: 'Só no "duplicado": o id do card aberto que fica. null caso contrário.' }
    },
    required: %w[motivo confidence reasoning duplicado_de],
    additionalProperties: false
  }.freeze

  def self.ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # Os arquivamentos que a IA fez (a atividade `archive` do sistema com `by: 'ai'`, Crm::Cards::Archiver); motivo: só os
  # daquele motivo.
  def self.arquivamentos(account_id, motivo: nil)
    Crm::Activity.where(account_id: account_id, event_type: 'archive', actor_type: 'system')
                 .where('payload @> ?', { by: 'ai', motivo: motivo }.compact.to_json)
  end

  # #2395: o card mais novo da conversa foi arquivado pela IA como "fora_do_negocio" (e ninguém o reabriu e arquivou
  # depois). A mensagem seguinte não recria card sozinha (Crm::Conversations::CardSyncer): sem isto, cada mensagem
  # recriava o card e a IA o arquivava de novo. O pedido novo ainda vira card pela IA de assunto (Crm::Subjects::Applier),
  # quando ela está ligada na caixa; ou pela mão de uma pessoa. Vale para a conversa inteira (todos os funis), por
  # BLOQUEIO_DA_RECRIACAO a contar do arquivamento; depois, a mensagem nova cria card como sempre.
  def self.conversa_fora_do_negocio?(conversation)
    vinculados = Crm::CardConversation.where(account_id: conversation.account_id, conversation_id: conversation.id).select(:card_id)
    cards = Crm::Card.where(account_id: conversation.account_id)
    ultimo = cards.where(conversation_id: conversation.id).or(cards.where(id: vinculados)).order(:id).last
    return false unless ultimo&.archived?

    ultimo_arquivamento = Crm::Activity.where(account_id: ultimo.account_id, card_id: ultimo.id, event_type: 'archive').order(:id).last
    recentes = arquivamentos(ultimo.account_id, motivo: 'fora_do_negocio').where(created_at: BLOQUEIO_DA_RECRIACAO.ago..)
    recentes.exists?(id: ultimo_arquivamento&.id)
  end

  # Os motivos aceitos na conta: com a flag da F3, também o "teste".
  def self.motivos(account)
    Crm::Ai::FecharCard.ligada?(account) ? [*MOTIVOS, MOTIVO_TESTE] : MOTIVOS
  end

  # O schema de um card (StageClassifier::CLASSIFICATION_SCHEMA) com o campo `nao_e_negocio` no fim, obrigatório. teste:
  # o enum do motivo com o "teste" (F3).
  def self.com_campo(schema, teste: false)
    corpo = schema[:schema]
    campo = teste ? CAMPO.deep_merge(properties: { motivo: { enum: [*MOTIVOS, MOTIVO_TESTE] } }) : CAMPO
    schema.merge(
      schema: corpo.merge(properties: corpo[:properties].merge(nao_e_negocio: campo), required: [*corpo[:required], 'nao_e_negocio'])
    ).freeze
  end

  # lido_em: quando a conversa foi lida para a avaliação (Crm::Ai::Evaluator#stage_classifier). origem: model_used e
  # trigger da sugestão do "era teste".
  def initialize(card:, decisao:, lido_em:, origem: {})
    @card = card
    @decisao = decisao.is_a?(Hash) ? decisao.with_indifferent_access : {}
    @lido_em = lido_em
    @origem = origem.to_h.with_indifferent_access
  end

  # true quando o card foi arquivado; a sugestão (Crm::AiStageSuggestion) no "era teste".
  def aplicar!
    return false unless decisao_valida?
    return sugerir_teste! if motivo == MOTIVO_TESTE

    arquivado = arquivar!
    Crm::Cards::Broadcaster.broadcast(@card, Events::Types::CRM_CARD_ARCHIVED) if arquivado
    arquivado
  end

  private

  def motivo = @decisao[:motivo].to_s

  def confianca = @decisao[:confidence].to_f

  # IA entende a conversa F3 (decisão do Rodrigo, 22/10): o "era teste" nunca arquiva sozinho, nem com confiança
  # máxima. Na rodada paga F5 o arquivamento errado (estresse-09:1) e o certo (c18-21:19) vieram os dois com 0,99: a
  # confiança não separa um do outro. Vira sugestão de fechar (Crm::Ai::FecharCard.aceitar! arquiva).
  def sugerir_teste!
    @card.with_lock do
      # O agente de cotação atendendo a conversa: a IA do CRM não sugere "era teste" por cima dele.
      next false unless pode_arquivar? && !Crm::Ai::FatosDaConversa.agente_protegido_atendendo?(@card)

      Crm::Ai::SuggestionRecorder.new(
        card: @card, from_stage: @card.stage, to_stage: @card.stage, confidence: confianca, reasoning: @decisao[:reasoning],
        model_used: @origem[:model_used], status: :pending,
        metadata: { trigger: @origem[:trigger], fechar: { resultado: Crm::Ai::FecharCard::ARQUIVADO, motivo: MOTIVO_TESTE },
                    lido_em: Crm::Ai::FecharCard.lido_em_para_gravar(@lido_em) }.compact
      ).perform
    end
  end

  # O "era teste" vira sugestão: basta a confiança de sugerir.
  def decisao_valida?
    minimo = motivo == MOTIVO_TESTE ? Crm::Ai::Config::SUGGESTION_THRESHOLD : Crm::Ai::Config::AUTO_MOVE_THRESHOLD
    self.class.motivos(@card.account).include?(motivo) && confianca >= minimo && @lido_em.present?
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

  # As guardas são relidas sob as travas do Crm::Cards::Archiver (lembretes antes do card, a ordem do DueProcessor).
  def arquivar!
    Crm::Cards::Archiver.new(card: @card, actor: nil, payload: payload).perform { pode_arquivar? }
  end

  def payload
    { by: 'ai', motivo: motivo, duplicado_de: @decisao[:duplicado_de], confidence: confianca,
      reasoning: @decisao[:reasoning].to_s.truncate(300) }.compact
  end
end
