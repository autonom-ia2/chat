class Crm::Ai::ScoreCalculator # rubocop:disable Metrics/ClassLength -- o contrato do modelo mora junto dos pesos (#1962)
  # Pesos calibrados contra 5 cards reais da conta 18 (30/07). A primeira versão dava 40 à distância
  # do próximo estágio e 18 à intenção: a Filomena, que perguntou valor total e parcelamento, saiu
  # com 5 (frio) porque disse "vou estudar" — um vendedor ligaria para ela no mesmo dia. Intenção e
  # sinal de compra passam a pesar mais que posição no funil.
  # v3, travada pelo golden set (spec/services/crm/ai/score_golden_set_spec.rb): 11 cenários reais
  # das contas 18 e 6 mais sintéticos de suporte/agendamento. Recalibrar = golden set inteiro verde.
  READINESS = { 'nenhuma' => 0, 'inicial' => 6, 'parcial' => 14, 'pronta' => 20 }.freeze
  INTENT = { 'baixa' => 0, 'media' => 15, 'alta' => 30 }.freeze
  URGENCY = { 'nenhuma' => 0, 'futura' => 3, 'proxima' => 8, 'imediata' => 20 }.freeze
  DECISION_MAKER = { 'sim' => 6, 'nao' => 0, 'desconhecido' => 0 }.freeze
  BLOCKER = { 'nenhum' => 0, 'leve' => -8, 'forte' => -20, 'negativo_explicito' => 0 }.freeze

  # #1962: número errado, "não é comigo", pediu para parar, mensagem automática sem pessoa. Não é
  # objeção a vencer: não existe negócio nesta conversa, então a nota vai a 0 na hora, por cima de
  # promessa, espera e piso. Com quem espera vindo do banco, é também a saída que impede uma
  # newsletter recebida de "esperar resposta" e subir para quente.
  EXPLICIT_NEGATIVE = 'negativo_explicito'.freeze

  # Pedido concreto de preço, prazo, parcelamento, link ou documento. Estava diluído em INTENT e é
  # forte demais para isso: é o momento em que o cliente sai de curioso e vira comprador.
  BUYING_SIGNAL_BONUS = 20

  # #1962: quem espera vem do BANCO (última mensagem real de cada lado), não do modelo. Antes era o
  # last_turn_owner da IA valendo +8 e um piso de 3 dias: na medição de 20/10, ~666 de 938 cards cuja
  # conversa tinha cliente esperando (waiting_since) estavam em frio. A dívida cresce com a espera — começa em BASE e soma
  # PER_DAY por dia até MAX — para que, entre dois clientes esperando, quem espera há mais tempo suba.
  CUSTOMER_WAITING_BONUS_BASE = 10
  CUSTOMER_WAITING_BONUS_PER_DAY = 2
  CUSTOMER_WAITING_BONUS_MAX = 20

  # Cliente esperando resposta nossa é no mínimo quente (55 = início da faixa) enquanto a dívida
  # vale: alguém precisa responder, mesmo que a conversa em si seja fraca.
  CUSTOMER_WAITING_FLOOR = 55

  # Validade da dívida nossa (espera do cliente, promessa, "falta dado nosso"). Até aqui ela não
  # decai; depois, volta a esfriar como o resto. Sem validade, 21 urgentes da amostra de 20/10
  # estavam parados há mais de 14 dias — alguns há 50–102, com a viagem já passada.
  DEBT_VALID_DAYS = 14

  # Promessa nossa não cumprida ("já envio o link") é o sinal mais forte que existe: o silêncio
  # deixa de ser desinteresse do cliente e passa a ser falha nossa. Também anula o decaimento —
  # até DEBT_VALID_DAYS de silêncio (#1962); depois, a promessa decai como o resto.
  UNFULFILLED_PROMISE_BONUS = 35

  # Decaimento: silêncio derruba a nota sozinho, sem chamar IA. Contado da ÚLTIMA MENSAGEM, nunca
  # da entrada no estágio — card pode mudar de estágio semanas depois da conversa morrer.
  # SEM teto (achado do review): com teto, card de base alta ficava preso em morno para sempre —
  # lead zumbi. Sem teto, base 100 chega a frio em ~42 dias de silêncio, que é o comportamento certo.
  DECAY_GRACE_DAYS = 2
  DECAY_PER_DAY = 2

  # Conversa ilegível (áudio sem transcrição, mensagens vazias): a IA não tem base para julgar,
  # então o score fica limitado em vez de inventado.
  UNREADABLE_CAP = 20

  # Mantidos em sincronia com SCORE_TIERS do CrmKanbanCard.vue. O teto do "sem promessa" fica em
  # ~92 para o topo não saturar: só promessa não cumprida encosta em 100.
  TIERS = [[19, 'frio'], [54, 'morno'], [83, 'quente'], [100, 'urgente']].freeze

  # Regra de produto: promessa NOSSA em aberto é urgente enquanto vale — a dívida é nossa.
  # Piso, não bônus: sem ele os rótulos oscilavam entre quente e urgente conforme os outros sinais.
  # O mesmo piso vale para cliente esperando com pedido de compra na mesa (#1962): o dinheiro está
  # parado do nosso lado. Na simulação de 20/10, levou "agora" em urgente de 6 para 13 de 29.
  UNFULFILLED_PROMISE_FLOOR = 85

  # #1962: "pronto para fechar, falta só um dado". O cliente já escolheu ou aceitou; só falta um
  # dado para emitir ou fechar. Se o dado é NOSSO, é dívida nossa (o piso da promessa); se é DELE, é
  # o empurrão que mais vale dar (o piso de quente). O bônus ordena dentro da faixa.
  READY_TO_CLOSE_BONUS = 20
  READY_TO_CLOSE_FLOOR = { 'falta_dado_nosso' => UNFULFILLED_PROMISE_FLOOR,
                           'falta_dado_do_cliente' => CUSTOMER_WAITING_FLOOR }.freeze

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
        enum: %w[nenhum leve forte negativo_explicito],
        description: 'Objeção aberta: "leve" = vou pensar; "forte" = recusa, concorrente, fora de escopo; ' \
                     '"negativo_explicito" = não há negócio com esta conversa: número errado, "não é comigo"/pessoa ' \
                     'errada, pediu para parar de receber mensagens, ou é mensagem automática sem pessoa do outro ' \
                     'lado (newsletter, propaganda, aviso de sistema). Em dúvida entre "forte" e ' \
                     '"negativo_explicito", use "forte".'
      },
      ready_to_close: {
        type: 'string',
        enum: %w[nao_se_aplica falta_dado_nosso falta_dado_do_cliente],
        description: 'O cliente JÁ escolheu ou aceitou (plano, proposta, horário) e só falta UM dado para emitir ou ' \
                     'fechar: "falta_dado_nosso" quando a pendência é nossa (link, boleto, apólice, confirmação); ' \
                     '"falta_dado_do_cliente" quando é dele (documento, CPF, data). "nao_se_aplica" em todo o resto, ' \
                     'inclusive quando ainda está escolhendo, negociando ou já fechou.'
      },
      buying_signal: {
        type: 'boolean',
        description: 'true quando o cliente pediu algo concreto para fechar (preço, valor total, parcelamento, prazo, ' \
                     'link de pagamento, envio de documento) E esse pedido segue de pé. Vale também quando está IMPLÍCITO: ' \
                     'cliente recebeu preço/proposta e seguiu conversando — reclamar do valor é negociação, não desistência. ' \
                     '("vou pensar", "depois te falo") MANTÉM o sinal. Recuo explícito ("não quero mais", "desisti", ' \
                     '"fechei com outro", "não é para mim") ZERA o sinal — use blocker=forte nesse caso.'
      },
      unfulfilled_promise: {
        type: 'boolean',
        description: 'true SOMENTE quando NÓS prometemos uma ação concreta (enviar link/proposta, retornar, verificar) e ela ' \
                     'segue NÃO ENTREGUE até a última mensagem. É false quando: a promessa foi cumprida depois na própria ' \
                     'conversa ("vou gerar agora" seguido da cotação enviada); a continuação depende de dado que o CLIENTE ' \
                     'ainda não mandou (idades, documentos, CNPJ — a pendência é dele); ou a pergunta do cliente foi ' \
                     'respondida, mesmo que negativamente. Aguardar resposta DO CLIENTE a algo já entregue NUNCA é ' \
                     'promessa nossa. Em dúvida, false.'
      },
      unreadable: { type: 'boolean', description: 'true quando não há conteúdo legível (áudio sem transcrição, mensagens vazias).' },
      reason: { type: 'string', maxLength: 140, description: 'Motivo em uma linha, exibido no card. Concreto, sem adjetivo vazio.' },
      evidence: { type: 'string', maxLength: 300, description: 'Trecho curto da conversa que sustenta os sinais.' }
    },
    required: %w[next_stage_readiness intent urgency decision_maker blocker ready_to_close buying_signal
                 unfulfilled_promise unreadable reason evidence],
    additionalProperties: false
  }.freeze

  Result = Struct.new(:value, :tier, :reason, :breakdown, keyword_init: true)

  # Exposto como método de classe: o ScoreDecayJob precisa rotular um valor recalculado por
  # decaimento puro (cards antigos, sem sinais gravados) sem instanciar o cálculo inteiro.
  def self.tier_for(value)
    TIERS.find { |ceiling, _| value <= ceiling }.last
  end

  # customer_waiting: o cliente mandou a última mensagem real (vem do banco, nunca do modelo). Com ele,
  # last_message_at é a mensagem do cliente, então o silêncio é também o tempo de espera.
  def initialize(signals:, last_message_at:, customer_waiting: false, terminal: false, now: Time.current)
    @signals = signals.respond_to?(:with_indifferent_access) ? signals.with_indifferent_access : {}
    @last_message_at = last_message_at
    @customer_waiting = customer_waiting == true
    @terminal = terminal
    @now = now
  end

  def perform
    return terminal_result if @terminal
    return explicit_negative_result if explicit_negative?

    value = [clamp(raw_points + decay_points), debt_floor].max
    # Teto de ilegível por ÚLTIMO (achado do review): é teto de confiança — sem conversa legível,
    # nenhum piso se sustenta, inclusive o de promessa.
    value = [value, UNREADABLE_CAP].min if flag(:unreadable)

    Result.new(value: value, tier: tier_for(value), reason: reason_text, breakdown: breakdown)
  end

  private

  def explicit_negative?
    text(:blocker) == EXPLICIT_NEGATIVE
  end

  # Recusa explícita cancela toda dívida (achado do review): se o cliente disse "fechei com outro",
  # a promessa não entregue e a espera viraram irrelevantes — não há ação comercial válida.
  def refused?
    text(:blocker) == 'forte'
  end

  # Conta o tempo exato, não dias inteiros: com 14 dias e 9 horas a dívida já venceu.
  def debt_valid?
    return false if refused?
    return true if @last_message_at.blank?

    @now - @last_message_at <= DEBT_VALID_DAYS.days
  end

  def promise_open?
    flag(:unfulfilled_promise) && debt_valid?
  end

  # Quem espera é fato do banco e continua verdadeiro depois da validade: o bônus fica. O que vence
  # em DEBT_VALID_DAYS é a proteção (piso e pausa do decaimento). A promessa é diferente: é leitura
  # do modelo, e depois de 14 dias de silêncio quase sempre já perdeu o sentido — perde o bônus também.
  def customer_waiting?
    @customer_waiting && !refused?
  end

  # O valor de ready_to_close que ainda vale, ou nil. Nota antiga, gravada antes do #1962, não tem o
  # campo: pesa como "nao_se_aplica".
  def ready_to_close
    value = text(:ready_to_close)
    value if READY_TO_CLOSE_FLOOR.key?(value) && debt_valid?
  end

  def owes_debt?
    promise_open? || ready_to_close.present? || (customer_waiting? && debt_valid?)
  end

  def debt_floor
    waiting = customer_waiting? && debt_valid?
    floors = [0]
    floors << UNFULFILLED_PROMISE_FLOOR if promise_open? || (waiting && flag(:buying_signal))
    floors << CUSTOMER_WAITING_FLOOR if waiting
    floors << READY_TO_CLOSE_FLOOR.fetch(ready_to_close) if ready_to_close
    floors.max
  end

  def terminal_result
    Result.new(value: 0, tier: 'frio', reason: 'Card encerrado.', breakdown: { terminal: true })
  end

  def explicit_negative_result
    Result.new(value: 0, tier: 'frio', reason: reason_text, breakdown: { explicit_negative: true })
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
      buying_signal: flag(:buying_signal) ? BUYING_SIGNAL_BONUS : 0,
      unfulfilled_promise: promise_open? ? UNFULFILLED_PROMISE_BONUS : 0,
      customer_waiting: customer_waiting? ? customer_waiting_bonus : 0,
      ready_to_close: ready_to_close ? READY_TO_CLOSE_BONUS : 0
    }
  end

  def customer_waiting_bonus
    days = @last_message_at.blank? ? 0 : idle_days
    [CUSTOMER_WAITING_BONUS_BASE + (days * CUSTOMER_WAITING_BONUS_PER_DAY), CUSTOMER_WAITING_BONUS_MAX].min
  end

  # Dívida nossa em aberto ignora o decaimento: o card não pode afundar por um silêncio que é nosso.
  # Vencida a validade, o silêncio conta inteiro, desde a última mensagem — como em qualquer card.
  def decay_points
    return 0 if owes_debt?
    return 0 if @last_message_at.blank?

    days = idle_days - DECAY_GRACE_DAYS
    return 0 if days <= 0

    -(days * DECAY_PER_DAY)
  end

  def idle_days
    ((@now - @last_message_at) / 1.day).floor
  end

  def tier_for(value)
    self.class.tier_for(value)
  end

  def reason_text
    provided = @signals[:reason].to_s.strip
    return provided.truncate(140) if provided.present?

    flag(:unfulfilled_promise) ? 'Promessa em aberto sem resposta nossa.' : 'Sem motivo informado.'
  end

  def text(key)
    @signals[key].to_s.strip.downcase
  end

  # Aceita true, "true" e 1: gateway compatível com a API do modelo às vezes devolve o booleano
  # como string, e comparar com == true silenciosamente perdia o sinal.
  def flag(key)
    ActiveModel::Type::Boolean.new.cast(@signals[key]) == true
  end

  def clamp(value)
    value.clamp(0, 100)
  end
end
