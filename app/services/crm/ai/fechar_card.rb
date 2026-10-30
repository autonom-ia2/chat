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
# Sempre sugestão (decisão do Rodrigo, 30/10, #2389): a IA nunca fecha o card sozinha, nem com o movimento automático
# do funil ligado e nem com confiança alta (os fechamentos errados da semana vieram com 0,95–0,99: a confiança não
# separa o certo do errado). A partir de Config::SUGGESTION_THRESHOLD, a decisão vira uma sugestão pendente
# (Crm::AiStageSuggestion, com o resultado, o motivo e a data de retorno em `metadata['fechar']`), e a pessoa fecha num
# clique (.aceitar!: o fechamento, com ela como autora, Crm::Ai::FecharCard::Aceite). Recusar não fecha nada.
#
# Guardas do código, relidas sob a trava do card (como Crm::Ai::NaoENegocio), para sugerir: card aberto;
# nenhuma mensagem do cliente depois de a conversa ser lida para esta avaliação; nenhuma pessoa escolheu a etapa ou o
# desfecho do card há menos de RESPEITO_AO_MOVIMENTO. O resto é do Crm::Ai::Evaluator: nunca no "Avaliar agora" (a
# pessoa olhando fecha se quiser) nem na avaliação do card parado (regra i: silêncio nunca fecha), e nunca com pedido ou
# promessa de pessoa na mesma resposta (fechar pularia a passagem).
#
# Sem a flag: o prompt, o schema e o comportamento são os de antes, palavra por palavra.
class Crm::Ai::FecharCard
  FLAG = 'crm_ia_fecha_card'.freeze
  RESULTADOS = %w[perdido resolvido].freeze
  MOTIVOS = %w[adiou recusou fechou_com_outra].freeze
  ADIOU = 'adiou'.freeze
  # A sugestão do "era teste" (Crm::Ai::NaoENegocio): aceita, o card é arquivado.
  ARQUIVADO = 'arquivado'.freeze
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
      - "recusou": o cliente recusou de forma clara e final o que oferecemos ou o atendimento, desistiu do pedido, disse
        que não tem mais interesse ou que chegou até nós sem querer pela nossa divulgação (clicou no anúncio, mandou a
        mensagem pronta ou preencheu o formulário por engano): esse lead é perda. Mensagem que era para outra pessoa e
        caiu neste número não é lead: não é perda.
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
  # pessoa fechou ou reabriu depois. Legado: desde o #2389 a IA não fecha mais card (o aceite grava a pessoa como ator e
  # não casa aqui), então só acha fechamentos de antes do deploy e fica vazio 24 h depois dele.
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

  # A sugestão de fechar que esperava sai da tela quando a conversa é lida de novo. Sob a trava do card, como o aceite
  # (Crm::Ai::FecharCard::Aceite): não passa por cima de uma sugestão que a pessoa aceitou nesse meio tempo.
  def self.expirar_sugestoes(card)
    card.with_lock { expirar_pendentes(card) }
  end

  def self.expirar_pendentes(card)
    card.account.crm_ai_stage_suggestions.where(card: card, status: :pending).where("metadata ->> 'fechar' IS NOT NULL")
        .find_each { |sugestao| sugestao.update!(status: :expired) }
  end

  # A pessoa aceitou a sugestão (Crm::Ai::FecharCard::Aceite). true quando o card fechou.
  def self.aceitar!(sugestao, ator:) = Aceite.new(sugestao, ator).perform

  # Quando a conversa foi lida para a sugestão, no metadata dela (`lido_em`): o aceite confere se o cliente escreveu
  # depois (Crm::Ai::FecharCard::Aceite). Com microssegundos, como o created_at da mensagem.
  def self.lido_em_para_gravar(lido_em) = lido_em&.utc&.iso8601(6)

  def self.lido_em_gravado(sugestao)
    valor = sugestao.metadata.to_h['lido_em']
    Time.iso8601(valor) if valor.is_a?(String) && valor.present?
  rescue ArgumentError
    nil
  end

  # A sugestão de fechar que esperava sai quando o card fecha por qualquer caminho (Crm::Cards::Closer, dentro da
  # transação dele). Só com a flag: sem ela, a sugestão de fechar nem aparece (Crm::AiStageSuggestion#fechar_desligado?).
  def self.expirar_ao_fechar(card)
    expirar_pendentes(card) if ligada?(card.account)
  end

  # lido_em: quando a conversa foi lida para a avaliação (Crm::Ai::Evaluator#stage_classifier). origem: model_used e
  # trigger da sugestão.
  def initialize(card:, decisao:, lido_em:, origem: {})
    @card = card
    @decisao = decisao.is_a?(Hash) ? decisao.with_indifferent_access : {}
    @lido_em = lido_em
    @origem = origem.to_h.with_indifferent_access
  end

  # A sugestão de fechar (Crm::AiStageSuggestion) ou nil. Nunca fecha: quem fecha é a pessoa que aceita.
  def aplicar!
    sugerir! if aplicavel?
  end

  private

  def resultado = @decisao[:resultado].to_s

  def motivo = @decisao[:motivo].to_s

  def confianca = @decisao[:confidence].to_f

  def perdido? = resultado == 'perdido'

  def aplicavel?
    RESULTADOS.include?(resultado) && decisao_valida? && confianca >= Crm::Ai::Config::SUGGESTION_THRESHOLD && @lido_em.present?
  end

  def decisao_valida?
    return false unless RESULTADOS.include?(resultado)
    return MOTIVOS.include?(motivo) if perdido?

    # Resolvido só fora da venda: num funil de venda, "deu certo" seria Ganho, que a IA nunca marca.
    !@card.pipeline.counts_as_sale?
  end

  def sugerir!
    @card.with_lock do
      next unless pode_fechar?

      Crm::Ai::SuggestionRecorder.new(
        card: @card, from_stage: @card.stage, to_stage: etapa_de_fim || @card.stage, confidence: confianca,
        reasoning: @decisao[:reasoning], model_used: @origem[:model_used], status: :pending,
        metadata: { trigger: @origem[:trigger], fechar: dados_da_sugestao, pedido_de_retorno: @origem[:pedido_de_retorno],
                    lido_em: self.class.lido_em_para_gravar(@lido_em) }.compact
      ).perform
    end
  end

  def dados_da_sugestao
    { resultado: resultado, motivo: (motivo if perdido?), retorno_em: (@decisao[:retorno_em].presence if motivo == ADIOU) }.compact
  end

  # O agente de cotação atendendo a conversa (Crm::Ai::FatosDaConversa.agente_protegido_atendendo?): a IA do CRM não
  # sugere fechar por cima dele.
  def pode_fechar?
    @card.open? && !mensagem_nova? && !pessoa_escolheu? && !Crm::Ai::FatosDaConversa.agente_protegido_atendendo?(@card)
  end

  # Sem a hora da leitura não há como saber se a decisão ficou velha: conta como mensagem nova.
  def mensagem_nova?
    return true if @lido_em.blank?

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

  def etapa_de_fim
    @card.pipeline.stages.order(:position, :id).find_by(perdido? ? { is_lost_stage: true } : { is_won_stage: true })
  end
end
