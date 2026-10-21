class Crm::Ai::ScoreCalculator
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
  # promessa, espera e piso.
  EXPLICIT_NEGATIVE = 'negativo_explicito'.freeze

  # Pedido concreto de preço, prazo, parcelamento, link ou documento. Estava diluído em INTENT e é
  # forte demais para isso: é o momento em que o cliente sai de curioso e vira comprador.
  BUYING_SIGNAL_BONUS = 20

  # #1962: cliente esperando resposta nossa = o BANCO diz que a última fala real é dele
  # (Crm::Conversations::LastTurns) E o modelo diz que ela pede resposta nossa (awaiting_our_reply). O banco
  # sozinho transformava "obrigado", "vou pensar" e newsletter em dívida nossa; o modelo sozinho (o antigo
  # last_turn_owner, +8) não existia no ScoreDecayJob. Nota gravada antes do #1962 não tem awaiting_our_reply:
  # vale "pede resposta" sempre que o banco diz que o cliente falou por último. Ignorar a espera nessas notas
  # derrubava a 1ª rodada do job (replay de 20/10: "agora" em urgente/quente caía de 20 para 9 de 29) até cada
  # card ser reavaliado pela IA, e reavaliar a base inteira em produção com IA paga não compensa. Quando o campo
  # existe, ele vale — inclusive o false.
  # A dívida cresce com a espera — começa em BASE e soma PER_DAY por dia até MAX — para que, entre dois
  # clientes esperando, quem espera há mais tempo suba.
  CUSTOMER_WAITING_BONUS_BASE = 10
  CUSTOMER_WAITING_BONUS_PER_DAY = 2
  CUSTOMER_WAITING_BONUS_MAX = 20

  # Cliente esperando resposta nossa é no mínimo quente (55 = início da faixa) enquanto a dívida
  # vale: alguém precisa responder, mesmo que a conversa em si seja fraca.
  CUSTOMER_WAITING_FLOOR = 55

  # Validade da dívida nossa (espera do cliente, promessa, "pronto para fechar"). Até aqui vale bônus e
  # piso; a dívida nossa também não decai. Depois, tudo isso cai e o card esfria a partir do FIM da
  # validade, não da última mensagem: sem isso, um urgente de 14 dias virava frio de uma rodada para a
  # outra. Sem validade, 21 urgentes da amostra de 20/10 estavam parados há mais de 14 dias — alguns
  # há 50–102, com a viagem já passada.
  DEBT_VALID_DAYS = 14

  # Promessa nossa não cumprida ("já envio o link") é o sinal mais forte que existe: o silêncio
  # deixa de ser desinteresse do cliente e passa a ser falha nossa. Também anula o decaimento —
  # até DEBT_VALID_DAYS de silêncio (#1962).
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

  # Mantidos em sincronia com SCORE_TIERS do CrmKanbanCard.vue. Depois do #1962 a soma dos bônus passa de
  # 100 (espera e pronto para fechar valem até 20 cada) e o topo satura: dois cards em 100 empatam. Fica
  # assim de propósito na fase 1 — o que decide o topo é o piso da dívida; desempatar dentro de 100 é
  # assunto da fase 2 (#1961), com prazo e valor.
  TIERS = [[19, 'frio'], [54, 'morno'], [83, 'quente'], [100, 'urgente']].freeze

  # Regra de produto: promessa NOSSA em aberto é urgente enquanto vale — a dívida é nossa.
  # Piso, não bônus: sem ele os rótulos oscilavam entre quente e urgente conforme os outros sinais.
  # O mesmo piso vale para cliente esperando com pedido de compra na mesa e SEM objeção (#1962): o
  # dinheiro está parado do nosso lado. Com objeção leve ("vou pensar", "achei caro") fica o piso de quente.
  UNFULFILLED_PROMISE_FLOOR = 85

  # #1962: "pronto para fechar, falta só um dado". O cliente já escolheu ou aceitou; só falta um
  # dado para emitir ou fechar. Se o dado é NOSSO, é dívida nossa (o piso da promessa, sem decair); se é
  # DELE, é o empurrão que mais vale dar (o piso de quente), mas o silêncio dele segue esfriando o card
  # até o piso. O bônus ordena dentro da faixa.
  READY_TO_CLOSE_BONUS = 20
  READY_TO_CLOSE_FLOOR = { 'falta_dado_nosso' => UNFULFILLED_PROMISE_FLOOR,
                           'falta_dado_do_cliente' => CUSTOMER_WAITING_FLOOR }.freeze

  Result = Struct.new(:value, :tier, :reason, :breakdown, keyword_init: true)

  # Exposto como método de classe: o ScoreDecayJob precisa rotular um valor recalculado por
  # decaimento puro (cards antigos, sem sinais gravados) sem instanciar o cálculo inteiro.
  def self.tier_for(value)
    TIERS.find { |ceiling, _| value <= ceiling }.last
  end

  # waiting_since: desde quando o cliente espera — a fala dele ainda sem resposta, numa conversa do card em que a
  # última fala real é dele. Vem do banco (Crm::Conversations::LastTurns), nunca do modelo; nil = ninguém espera.
  def initialize(signals:, last_message_at:, waiting_since: nil, terminal: false, now: Time.current)
    @signals = signals.respond_to?(:with_indifferent_access) ? signals.with_indifferent_access : {}
    @last_message_at = last_message_at
    @waiting_since = waiting_since
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

  # Conta o tempo exato, não dias inteiros: com 14 dias e 9 horas a dívida já venceu. Sem âncora (card sem
  # mensagem real) não há dívida: não se deve resposta a uma conversa que não existe.
  def within_validity?(anchor)
    anchor.present? && @now - anchor <= DEBT_VALID_DAYS.days
  end

  # Sinais que fazem dívida, valendo ou vencida. Recusa explícita cancela todos.
  def promise_signal?
    flag(:unfulfilled_promise) && !refused?
  end

  def waiting_signal?
    @waiting_since.present? && asks_for_reply? && !refused?
  end

  # Chave ausente = nota antiga (ver CUSTOMER_WAITING_BONUS_BASE): conta como "pede resposta". Chave presente vale
  # como veio: null ou valor malformado de gateway não é "pede" (achado do review).
  def asks_for_reply?
    @signals.key?(:awaiting_our_reply) ? flag(:awaiting_our_reply) : true
  end

  # O valor de ready_to_close, ou nil. Nota antiga, gravada antes do #1962, não tem o campo: pesa como
  # "nao_se_aplica".
  def ready_to_close_signal
    value = text(:ready_to_close)
    value if READY_TO_CLOSE_FLOOR.key?(value) && !refused?
  end

  def promise_open?
    promise_signal? && within_validity?(@last_message_at)
  end

  def waiting?
    waiting_signal? && within_validity?(@waiting_since)
  end

  def ready_to_close
    ready_to_close_signal if within_validity?(@last_message_at)
  end

  # Só o que é NOSSO segura o decaimento. "Falta dado do cliente" mantém o piso, mas o silêncio é dele.
  def owes_debt?
    promise_open? || waiting? || ready_to_close == 'falta_dado_nosso'
  end

  def debt_floor
    floors = [0]
    floors << UNFULFILLED_PROMISE_FLOOR if promise_open? || (waiting? && flag(:buying_signal) && text(:blocker) == 'nenhum')
    floors << CUSTOMER_WAITING_FLOOR if waiting?
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
      customer_waiting: waiting? ? customer_waiting_bonus : 0,
      ready_to_close: ready_to_close ? READY_TO_CLOSE_BONUS : 0
    }
  end

  def customer_waiting_bonus
    [CUSTOMER_WAITING_BONUS_BASE + (days_since(@waiting_since) * CUSTOMER_WAITING_BONUS_PER_DAY), CUSTOMER_WAITING_BONUS_MAX].min
  end

  # Dívida nossa em aberto ignora o decaimento: o card não pode afundar por um silêncio que é nosso.
  def decay_points
    return 0 if owes_debt?

    anchor = decay_anchor
    return 0 if anchor.blank?

    days = days_since(anchor) - DECAY_GRACE_DAYS
    return 0 if days <= 0

    -(days * DECAY_PER_DAY)
  end

  # Card cuja dívida NOSSA venceu esfria a partir do fim da validade, não da última mensagem: o tempo em que o
  # silêncio era nosso não conta contra ele. Aqui a dívida já não vale (owes_debt? é falso), então sinal de dívida
  # nossa presente = dívida vencida. "Falta dado do cliente" não entra: o silêncio sempre foi dele.
  def decay_anchor
    return if @last_message_at.blank?

    ends = [@last_message_at]
    ends << (@last_message_at + DEBT_VALID_DAYS.days) if promise_signal? || ready_to_close_signal == 'falta_dado_nosso'
    ends << (@waiting_since + DEBT_VALID_DAYS.days) if waiting_signal?
    ends.max
  end

  def days_since(time)
    ((@now - time) / 1.day).floor
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
