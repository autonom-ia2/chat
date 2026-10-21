# IA entende a conversa, F3 — a IA fecha o card (flag de conta `crm_ia_fecha_card`).
#
# A IA de etapa só sabia mover entre etapas: "Perdido" era uma coluna, e o card seguia aberto, sem motivo, contando
# como pedido em andamento. Com a flag, o modelo pode dizer, no campo `fechar_card` da mesma avaliação (nenhuma
# chamada nova), que o pedido DESTE card terminou. Quem lê a conversa é ele; o código só confere o que é estrutural.
#
# - "perdido" com motivo: "adiou" (agora não, sem recusar; em qualquer funil, regra a), "recusou" ou
#   "fechou_com_outra". O card vai para a etapa de perda do funil, se houver, e fecha como Perdido (Cancelado num funil
#   de Atender, Crm::Cards::Outcome). O motivo vai em `lost_reason`, com o rótulo da língua da conta. No "adiou", um
#   lembrete de retorno (Retorno) na data que o cliente disse ou, sem data, em RETORNO_DO_ADIOU.
# - "resolvido": só em funil que não conta como venda (Atender), com confirmação do cliente (regra j; o texto da conta
#   dizer que quem fecha é a equipe também é leitura do modelo). Vai para a etapa de ganho do funil, se houver, e fecha
#   como Resolvido.
# - Ganho nunca (regra c): o campo não tem esse resultado, e num funil de venda o código recusa o "resolvido".
#
# Guardas do código, relidas sob a trava do card (como Crm::Ai::NaoENegocio): card aberto; confiança da do movimento
# automático; nenhuma mensagem do cliente depois de a conversa ser lida para esta avaliação; nenhuma pessoa escolheu a
# etapa ou o desfecho do card há menos de RESPEITO_AO_MOVIMENTO. O resto é do Crm::Ai::Evaluator: só no automático do
# funil, nunca no "Avaliar agora" (a pessoa olhando fecha se quiser) nem na avaliação do card parado (regra i: silêncio
# nunca fecha), e nunca com pedido ou promessa de pessoa na mesma resposta (fechar pularia a passagem).
#
# Sem a flag: o prompt, o schema e o comportamento são os de antes, palavra por palavra.
class Crm::Ai::FecharCard
  FLAG = 'crm_ia_fecha_card'.freeze
  RESULTADOS = %w[perdido resolvido].freeze
  MOTIVOS = %w[adiou recusou fechou_com_outra].freeze
  ADIOU = 'adiou'.freeze
  # A avaliação do card parado (Crm::Ai::StaleCardsJob, com a flag): nunca fecha.
  TRIGGER_CARD_PARADO = 'card_parado'.freeze
  GATILHOS_SEM_FECHAMENTO = ['manual', TRIGGER_CARD_PARADO].freeze
  RETORNO_DO_ADIOU = 30.days
  EVENTOS_DE_FECHAMENTO = %w[won lost resolved cancelled].freeze
  # O que uma pessoa faz no card que a IA respeita: escolher a etapa ou o desfecho (criar escolhendo a etapa também).
  ESCOLHAS_DA_PESSOA = [*Crm::Ai::Evaluator::ESCOLHAS_DE_ETAPA, *EVENTOS_DE_FECHAMENTO, 'archive'].freeze

  CAMPO = {
    type: %w[object null],
    description: 'Preencha SOMENTE quando a conversa mostra que o pedido deste card terminou (FECHAR O CARD). null caso contrário.',
    properties: {
      resultado: { type: 'string', enum: RESULTADOS },
      motivo: { type: %w[string null], enum: [*MOTIVOS, nil], description: 'Só no "perdido". null no "resolvido".' },
      retorno_em: { type: %w[string null], description: 'Só no "adiou", quando o cliente disse quando retomar: "YYYY-MM-DD". Senão null.' },
      confidence: { type: 'number', minimum: 0, maximum: 1 },
      reasoning: { type: 'string', maxLength: 300, description: 'A fala do cliente que mostra o fim.' }
    },
    required: %w[resultado motivo retorno_em confidence reasoning],
    additionalProperties: false
  }.freeze

  # Vai no FIM do prefixo da IA de etapa (Crm::Ai::ClassifierPrompt.para), só com a flag: o prefixo das contas sem ela
  # não muda.
  INSTRUCAO = <<~FECHAR.strip
    FECHAR O CARD ("fechar_card"):
    Preencha só quando a conversa mostra que o pedido DESTE card terminou:
    - "resultado": "perdido", com "motivo":
      - "adiou": o cliente disse que agora não, que vai pensar, que deixa para depois ou que volta a falar mais tarde,
        SEM recusar. Vale em qualquer tipo de funil. Se ele disse quando quer retomar, ponha em "retorno_em" a data
        ("YYYY-MM-DD", resolvida a partir de "now_local"); sem data dita por ele, null.
      - "recusou": o cliente recusou de forma clara e final o que oferecemos ou o atendimento.
      - "fechou_com_outra": o cliente disse que fechou ou resolveu com outra empresa ou pessoa.
    - "resultado": "resolvido", só em "pipeline.kind" = "serve": o CLIENTE confirmou com clareza que o problema DESTE
      card foi resolvido, e nenhum texto do funil, das etapas ou do handoff_trigger diz que quem encerra o atendimento
      é a equipe. "motivo" e "retorno_em": null.
    NUNCA preencha quando: só houve silêncio, demora ou falta de resposta, por mais longa que seja; a fala é sobre outro
    pedido; o cliente ainda pergunta, negocia ou pede algo; quem disse que acabou foi a equipe, o nosso assistente ou
    outro sistema, e não o cliente; houver dúvida. Ganho nunca é marcado por este campo: quando o cliente fecha conosco,
    vale a etapa, como sempre.
    Com "fechar_card" preenchido, suggested_stage_id é a etapa de fim que corresponde a ele, se houver; senão o estágio
    atual. "confidence" segue a escala de CONFIANÇA; "reasoning" cita a fala do cliente. Nos outros casos, null.
    VOLTAR DE ETAPA: voltar o card a uma etapa anterior é permitido quando a conversa contradiz a etapa atual com
    evidência explícita (o que a etapa atual pressupõe deixou de valer). Na dúvida, mantenha.
  FECHAR

  # Regra k ("era teste"): vai junto, só quando a conta também tem o "não é negócio" (Crm::Ai::NaoENegocio). O card sai
  # arquivado, sem contar como perda.
  TESTE = <<~TESTE.strip
    "nao_e_negocio" também aceita "motivo": "teste": quem escreveu disse que a conversa era só um teste (de quem
    configura ou confere o atendimento) e não há pedido de verdade. "duplicado_de": null.
  TESTE

  def self.ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # O schema de um card com o campo `fechar_card` no fim, obrigatório.
  def self.com_campo(schema)
    corpo = schema[:schema]
    schema.merge(
      schema: corpo.merge(properties: corpo[:properties].merge(fechar_card: CAMPO), required: [*corpo[:required], 'fechar_card'])
    ).freeze
  end

  # Regra do respeito de 24 h (Crm::Subjects::Applier): os cards da conta fechados pela IA desde `desde`, que nenhuma
  # pessoa fechou ou reabriu depois. O fechamento da IA não é fechamento de uma pessoa.
  def self.fechados_pela_ia(account, desde)
    recentes = Crm::Activity.where(account_id: account.id, created_at: desde..)
    pela_ia = recentes.where(event_type: EVENTOS_DE_FECHAMENTO, actor_type: 'system').where('payload @> ?', { by: 'ai' }.to_json)
    pela_pessoa = recentes.where(event_type: [*EVENTOS_DE_FECHAMENTO, 'reopen'], actor_type: 'user')
    pela_ia.distinct.pluck(:card_id) - pela_pessoa.distinct.pluck(:card_id)
  end

  # O retorno do "adiou", depois de fechar. Best-effort, como o retorno de sempre (Crm::Ai::Evaluator#run_callback).
  def self.agendar_retorno(card, decisao, pedido_de_retorno = nil)
    dados = decisao.is_a?(Hash) ? decisao.with_indifferent_access : {}
    return unless dados[:resultado] == 'perdido' && dados[:motivo] == ADIOU
    return unless Crm::Ai::Config.callback_detection_enabled? && Crm::Ai::Config.pipeline_callback_enabled?(card.pipeline)

    Retorno.new(card: card, retorno_em: dados[:retorno_em], pedido_de_retorno: pedido_de_retorno).perform
  rescue StandardError => e
    Rails.logger.error("[CRM AI fechar_card retorno] #{e.class}: #{e.message}")
    nil
  end

  # lido_em: quando a conversa foi lida para a avaliação (Crm::Ai::Evaluator#stage_classifier).
  def initialize(card:, decisao:, lido_em:)
    @card = card
    @decisao = decisao.is_a?(Hash) ? decisao.with_indifferent_access : {}
    @lido_em = lido_em
  end

  # true quando o card foi fechado.
  def aplicar!
    return false unless decisao_valida?

    fechado = @card.with_lock { pode_fechar? && fechar! }
    Crm::Cards::Broadcaster.broadcast(@card, Events::Types::CRM_CARD_UPDATED) if fechado
    fechado
  end

  private

  def resultado = @decisao[:resultado].to_s

  def motivo = @decisao[:motivo].to_s

  def confianca = @decisao[:confidence].to_f

  def perdido? = resultado == 'perdido'

  def decisao_valida?
    return false unless RESULTADOS.include?(resultado) && confianca >= Crm::Ai::Config::AUTO_MOVE_THRESHOLD && @lido_em.present?
    return MOTIVOS.include?(motivo) if perdido?

    # Resolvido só fora da venda: num funil de venda, "deu certo" seria Ganho, que a IA nunca marca.
    !@card.pipeline.counts_as_sale?
  end

  def pode_fechar?
    @card.open? && !mensagem_nova? && !pessoa_escolheu?
  end

  def mensagem_nova?
    conversas = [@card.conversation_id, *@card.card_conversations.pluck(:conversation_id)].compact.uniq
    Message.where(account_id: @card.account_id, conversation_id: conversas, message_type: :incoming)
           .exists?(['created_at > ?', @lido_em])
  end

  def pessoa_escolheu?
    da_pessoa = Crm::Activity.where(account_id: @card.account_id, card_id: @card.id, actor_type: 'user',
                                    created_at: Crm::Ai::Evaluator::RESPEITO_AO_MOVIMENTO.ago..)
    criou_na_etapa = da_pessoa.where(event_type: 'create').where('payload @> ?', { etapa_escolhida: true }.to_json)
    da_pessoa.where(event_type: ESCOLHAS_DA_PESSOA).or(criou_na_etapa).exists?
  end

  def fechar!
    ir_para_etapa_de_fim!
    @card.account.crm_ai_stage_suggestions.where(card: @card, status: :pending).find_each { |sugestao| sugestao.update!(status: :expired) }
    Crm::Cards::Closer.new(card: @card, actor: nil, result: perdido? ? 'lost' : 'won', lost_reason: rotulo_do_motivo,
                           payload_extra: payload).perform
    true
  end

  # A etapa de perda (ou, no resolvido, a de ganho do funil de Atender), como uma pessoa que arrasta o card antes de
  # fechar. Sem ela, o card fecha onde está.
  def ir_para_etapa_de_fim!
    etapa = @card.pipeline.stages.order(:position, :id).find_by(perdido? ? { is_lost_stage: true } : { is_won_stage: true })
    return if etapa.nil? || etapa.id == @card.stage_id

    Crm::Cards::Mover.new(card: @card, actor: nil, target_stage: etapa, automation_context: { source: 'crm_ai' }).perform
  end

  def rotulo_do_motivo
    return unless perdido?

    I18n.t("crm.ai_fechar_card.motivos.#{motivo}", locale: @card.account.locale.presence || I18n.default_locale)
  end

  def payload
    { by: 'ai', motivo: (motivo if perdido?), retorno_em: (@decisao[:retorno_em].presence if motivo == ADIOU),
      confidence: confianca, reasoning: @decisao[:reasoning].to_s.truncate(300) }.compact
  end
end
