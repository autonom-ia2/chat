class Crm::Ai::ScoreCalculator
  READINESS = { 'nenhuma' => 0, 'inicial' => 10, 'parcial' => 25, 'pronta' => 40 }.freeze
  INTENT = { 'baixa' => 0, 'media' => 8, 'alta' => 18 }.freeze
  URGENCY = { 'nenhuma' => 0, 'futura' => 3, 'proxima' => 12, 'imediata' => 22 }.freeze
  DECISION_MAKER = { 'sim' => 8, 'nao' => 0, 'desconhecido' => 0 }.freeze
  BLOCKER = { 'nenhum' => 0, 'leve' => -8, 'forte' => -20 }.freeze

  # Quem falou por último decide de quem é a dívida: cliente falou = nós devemos resposta.
  LAST_TURN_OWNER = { 'cliente' => 10, 'humano' => -5, 'agente_plataforma' => 0, 'agente_externo' => 0 }.freeze

  # Promessa nossa não cumprida ("já envio o link") é o sinal mais forte que existe: o silêncio
  # deixa de ser desinteresse do cliente e passa a ser falha nossa. Também anula o decaimento.
  UNFULFILLED_PROMISE_BONUS = 35

  # Decaimento: silêncio derruba a nota sozinho, sem chamar IA. Contado da ÚLTIMA MENSAGEM, nunca
  # da entrada no estágio — card pode mudar de estágio semanas depois da conversa morrer.
  DECAY_GRACE_DAYS = 2
  DECAY_PER_DAY = 2
  MAX_DECAY = 40

  # Conversa ilegível (áudio sem transcrição, mensagens vazias): a IA não tem base para julgar,
  # então o score fica limitado em vez de inventado.
  UNREADABLE_CAP = 20

  TIERS = [[29, 'frio'], [59, 'morno'], [84, 'quente'], [100, 'urgente']].freeze

  # Contrato de saída do modelo. Fica aqui, não no StageClassifier: quem define o vocabulário dos
  # sinais é quem sabe pesá-los. O classifier apenas consome.
  SIGNALS_SCHEMA = {
    type: 'object',
    description: 'Sinais para pontuar a prioridade de atenção humana neste card.',
    properties: {
      next_stage_readiness: {
        type: 'string',
        enum: %w[nenhuma inicial parcial pronta],
        description: 'Quanto a conversa JÁ atende ao critério do PRÓXIMO estágio do funil (não do atual).'
      },
      intent: {
        type: 'string',
        enum: %w[baixa media alta],
        description: 'Intenção do cliente de avançar (pediu preço, prazo, link, documento).'
      },
      urgency: {
        type: 'string',
        enum: %w[nenhuma futura proxima imediata],
        description: 'Urgência pela DATA citada na conversa (embarque, vencimento, consulta): "futura" = meses, "imediata" = dias.'
      },
      decision_maker: { type: 'string', enum: %w[desconhecido nao sim], description: 'A pessoa na conversa decide a contratação.' },
      blocker: {
        type: 'string',
        enum: %w[nenhum leve forte],
        description: 'Objeção aberta: "leve" = vou pensar; "forte" = recusa, concorrente, fora de escopo.'
      },
      last_turn_owner: {
        type: 'string',
        enum: %w[cliente humano agente_plataforma agente_externo],
        description: 'Quem enviou a ÚLTIMA mensagem. Use os papéis de recent_messages.'
      },
      unfulfilled_promise: {
        type: 'boolean',
        description: 'true quando NÓS prometemos uma ação concreta (enviar link, retornar, verificar) e ela não foi entregue depois.'
      },
      unreadable: { type: 'boolean', description: 'true quando não há conteúdo legível (áudio sem transcrição, mensagens vazias).' },
      reason: { type: 'string', maxLength: 140, description: 'Motivo em uma linha, exibido no card. Concreto, sem adjetivo vazio.' },
      evidence: { type: 'string', maxLength: 300, description: 'Trecho curto da conversa que sustenta os sinais.' }
    },
    required: %w[next_stage_readiness intent urgency decision_maker blocker last_turn_owner unfulfilled_promise unreadable reason evidence],
    additionalProperties: false
  }.freeze

  Result = Struct.new(:value, :tier, :reason, :breakdown, keyword_init: true)

  def initialize(signals:, last_message_at:, terminal: false, now: Time.current)
    @signals = signals.respond_to?(:with_indifferent_access) ? signals.with_indifferent_access : {}
    @last_message_at = last_message_at
    @terminal = terminal
    @now = now
  end

  def perform
    return terminal_result if @terminal

    value = clamp(raw_points + decay_points)
    value = [value, UNREADABLE_CAP].min if flag(:unreadable)

    Result.new(value: value, tier: tier_for(value), reason: reason_text, breakdown: breakdown)
  end

  private

  def terminal_result
    Result.new(value: 0, tier: 'frio', reason: 'Card encerrado.', breakdown: { terminal: true })
  end

  def raw_points
    breakdown.values.sum
  end

  def breakdown
    @breakdown ||= {
      readiness: READINESS.fetch(text(:next_stage_readiness), 0),
      intent: INTENT.fetch(text(:intent), 0),
      urgency: URGENCY.fetch(text(:urgency), 0),
      decision_maker: DECISION_MAKER.fetch(text(:decision_maker), 0),
      blocker: BLOCKER.fetch(text(:blocker), 0),
      last_turn_owner: LAST_TURN_OWNER.fetch(text(:last_turn_owner), 0),
      unfulfilled_promise: flag(:unfulfilled_promise) ? UNFULFILLED_PROMISE_BONUS : 0
    }
  end

  # Promessa aberta ignora o decaimento: o card não pode afundar por um silêncio que é nosso.
  def decay_points
    return 0 if flag(:unfulfilled_promise)
    return 0 if @last_message_at.blank?

    idle_days = ((@now - @last_message_at) / 1.day).floor - DECAY_GRACE_DAYS
    return 0 if idle_days <= 0

    -[idle_days * DECAY_PER_DAY, MAX_DECAY].min
  end

  def tier_for(value)
    TIERS.find { |ceiling, _| value <= ceiling }.last
  end

  def reason_text
    provided = @signals[:reason].to_s.strip
    return provided.truncate(140) if provided.present?

    flag(:unfulfilled_promise) ? 'Promessa em aberto sem resposta nossa.' : 'Sem motivo informado.'
  end

  def text(key)
    @signals[key].to_s.strip.downcase
  end

  def flag(key)
    @signals[key] == true
  end

  def clamp(value)
    value.clamp(0, 100)
  end
end
