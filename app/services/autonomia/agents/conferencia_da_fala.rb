# A FALA DA LIA NÃO PROMETE PARA DEPOIS, NÃO CONTRADIZ A COTAÇÃO E NÃO MOSTRA A ENGRENAGEM (#510, #511 e #547,
# parte do #420).
#
# Os três primeiros defeitos têm a mesma forma: a fala sai dizendo algo que o estado do turno desmente. O
# quarto é de voz, e a régua dele é o que o CLIENTE lê.
#
#   - #510: ela promete consultar ou confirmar DEPOIS, e nenhuma ferramenta rodou no turno. Não existe turno
#     seguinte sem mensagem nova do cliente, então a promessa fica pendurada.
#   - #511: ela diz que a cotação continua correndo, e a cotação que corria no começo do turno fechou antes de a
#     fala sair. O modelo leu o estado antigo.
#   - #547: ela promete o comparativo e não há cotação nenhuma. Medido na conversa 6983, em 20/09/2026: o cliente
#     mandou tudo, ela disse "o comparativo das seguradoras chega por aqui quando ficar pronto", e zero execuções
#     foram criadas. Aqui o que desmente a fala é a AUSÊNCIA de cotação, não o fechamento dela.
#   - #547: ela mostra ao cliente a engrenagem que é nossa ("vou passar para o especialista de seguro auto").
#
# O código só confere. Quem reescreve é o modelo, uma vez, com as ferramentas do turno à mão (o `Answerer`).
class Autonomia::Agents::ConferenciaDaFala
  # Promessa de ação futura que depende de consulta: "vou confirmar nas condições", "deixa eu verificar",
  # "já te retorno", "assim que eu consultar".
  PROMESSA = [
    /\b(?:vou|irei|deixa\s+eu|deix[ae]-me)\s+(?:\S+\s+){0,2}?(?:confirmar|verificar|consultar|checar|conferir|pesquisar)\b/i,
    /\b(?:vou|deixa\s+eu)\s+dar\s+uma\s+olhada\b/i,
    /\b(?:j[áa]\s+(?:te\s+|lhe\s+)?(?:retorno|volto|respondo)|(?:te|lhe)\s+retorno|volto\s+(?:j[áa]|logo|em\s+seguida))\b/i,
    /\bassim\s+que\s+(?:eu\s+)?(?:confirmar|verificar|consultar|checar)\b/i
  ].freeze

  # A fala afirma que a cotação ainda corre ou que o comparativo ainda vai chegar.
  AINDA_CORRENDO = [
    /\bcota[çc][ãa]o\b[^.!?\n]{0,30}\b(?:continua|segue|ainda)\b[^.!?\n]{0,20}\b(?:correndo|andamento|rodando)\b/i,
    /\bcomparativo\b[^.!?\n]{0,40}\b(?:chega|chegar|chegar[áa]|vai\s+chegar|sai|sair[áa]|vai\s+sair|ficar?\s+pronto)\b/i
  ].freeze

  # A fala promete ao cliente uma cotação ou um comparativo que ainda vai chegar. Inclui `AINDA_CORRENDO`: a
  # mesma frase ("o comparativo chega por aqui") é legítima com cotação correndo e é promessa vazia sem nenhuma.
  PROMESSA_DE_COTACAO = (AINDA_CORRENDO + [
    /\b(?:vou|irei|vamos)\s+(?:\S+\s+){0,3}?(?:cotar|cota[çc][ãa]o)\b/i,
    /\b(?:pre[çc]os|op[çc][õo]es|valores)\b[^.!?\n]{0,40}\b(?:chegam?|chegar[ãa]?o?|saem|sair[ãa]o|ficam?\s+pront[oa]s?)\b/i
  ]).freeze

  # VOCABULÁRIO INTERNO NA FALA AO CLIENTE (#547). A engrenagem é nossa: quem fala com ele é a Lia, do começo ao
  # fim. A régua é o que o CLIENTE lê, então a lista é curta e cada entrada tem o motivo:
  #   - "especialista": decisão do CEO em 20/09/2026. Ele não sabe que existe especialista de ramo, e a passagem
  #     para um humano é decisão dela, dita nas palavras dela.
  #   - "ferramenta", "fluxo", "prompt", "agente": jargão nosso, sem uso legítimo numa conversa de seguro.
  #   - "sistema": quase sempre o nosso. A exceção real é o sistema DA SEGURADORA, que é coisa dela e o cliente
  #     entende assim; só ela fica de fora, pelo lookahead.
  # "modelo" ficou FORA de propósito: em auto é o modelo do veículo, e o falso positivo seria diário.
  VOCABULARIO_INTERNO = [
    /\bespecialistas?\b/i,
    /\bferramentas?\b/i,
    /\bfluxos?\b/i,
    /\bprompts?\b/i,
    /\bagentes?\b/i,
    /\bsistemas?\b(?!\s+d[ao]s?\s+segurador)/i
  ].freeze

  # -> a execução de `cotar_seguro` que corre agora na conversa, ou nil. Lida no começo do turno, antes do modelo.
  def self.cotacao_correndo(conversation_id)
    leitura = ::Autonomia::Insurance::ResultadoDaCotacao.da_conversa(conversation_id)
    leitura&.correndo? ? leitura.run : nil
  end

  def initialize(conversa:, cotacao_no_inicio:)
    @conversa = conversa
    @cotacao_no_inicio = cotacao_no_inicio
  end

  # -> os sinais que a fala dispara (`:promessa`, `:cotacao_fechada`, `:cotacao_prometida`,
  # `:vocabulario_interno`); vazio quando ela pode sair como está.
  # Com escalada a promessa não fica pendurada: quem segue é o atendente. Vale para as duas promessas, pela
  # mesma razão. O vocabulário não: é justamente ao escalar que "o especialista" escapa.
  def sinais(reply, ferramentas_no_turno:, escalou: false)
    texto = reply.to_s
    fechada = casa?(texto, AINDA_CORRENDO) && fechou_no_turno?
    [(:promessa if promessa?(texto, ferramentas_no_turno, escalou)),
     (:cotacao_fechada if fechada),
     (:cotacao_prometida if prometida?(texto, escalou, fechada)),
     (:vocabulario_interno if casa?(texto, VOCABULARIO_INTERNO))].compact
  end

  # -> o pedido de reescrita ao modelo para estes sinais.
  def pedido(sinais)
    partes = []
    partes << pedido_da_promessa if sinais.include?(:promessa)
    partes << pedido_da_cotacao if sinais.include?(:cotacao_fechada)
    partes << pedido_da_cotacao_prometida if sinais.include?(:cotacao_prometida)
    partes << pedido_do_vocabulario if sinais.include?(:vocabulario_interno)
    (partes + ['Reescreva a resposta ao cliente em reply, mantendo o resto do que ela diz. Sem travessão.']).join("\n\n")
  end

  private

  # #510: promete consultar depois e nenhuma ferramenta rodou no turno.
  def promessa?(texto, ferramentas_no_turno, escalou)
    !escalou && ferramentas_no_turno.zero? && casa?(texto, PROMESSA)
  end

  # #547: promete a cotação ou o comparativo e não há cotação nenhuma viva. A que fechou neste turno já é
  # `:cotacao_fechada`, que diz outra coisa ao modelo; os dois sinais nunca saem juntos.
  def prometida?(texto, escalou, fechada)
    !escalou && !fechada && casa?(texto, PROMESSA_DE_COTACAO) && sem_cotacao_viva? && !fechou_no_turno?
  end

  def casa?(texto, padroes)
    padroes.any? { |re| texto.match?(re) }
  end

  def pedido_da_promessa
    'A sua resposta promete verificar, consultar ou confirmar algo depois, e nenhuma ferramenta foi chamada ' \
      'neste turno. Não existe depois: o cliente só recebe outra mensagem sua quando escrever de novo. Se ' \
      'precisa consultar, chame a ferramenta agora e responda com o resultado. Se não precisa, responda com o ' \
      'que você já sabe. Se o que falta é algo que o cliente tem de mandar, peça a ele.'
  end

  def pedido_da_cotacao
    entregue = leitura_final.comparativo_enviado? ? ', e o comparativo em PDF já foi entregue ao cliente' : ''
    "A cotação desta conversa terminou enquanto você respondia#{entregue}. Não diga que ela continua correndo " \
      'nem que o comparativo ainda vai chegar.'
  end

  def pedido_da_cotacao_prometida
    'A sua resposta diz ao cliente que a cotação ou o comparativo vai chegar, e não existe cotação correndo ' \
      'nesta conversa: nada foi acionado, e ninguém vai produzir esse comparativo. Ou você aciona a cotação ' \
      'agora, com a ferramenta do ramo, e responde contando que ela está em andamento, ou responde sem ' \
      'prometer comparativo nenhum. Se falta dado para cotar, peça à pessoa exatamente o que falta.'
  end

  def pedido_do_vocabulario
    'A sua resposta mostra a nossa engrenagem, e o cliente não conhece nenhuma parte dela: ele fala com você, ' \
      'do começo ao fim. Ele nunca ouve falar de especialista, ferramenta, fluxo, prompt, agente nem do nosso ' \
      'sistema. Conte o que acontece do lado dele: o que você está fazendo, o que ele recebe e quando. Se quem ' \
      'segue a conversa é uma pessoa da equipe, diga isso com as suas palavras, sem dar nome à engrenagem.'
  end

  # -> NÃO existe execução de `cotar_seguro` viva nesta conversa NESTE instante. Viva é a que corre desde antes
  # do turno e também a aceita agora, que espera o fim dele em `pending` (só o Responder promove): uma leitura
  # que olhasse apenas `correndo?` perderia a cotação legítima que a Lia acabou de acionar. Sem memória de
  # propósito: a reescrita pode acionar a cotação, e aí o sinal tem de sumir na releitura. Sem conversa não há
  # o que conferir, e o conferente não é portão: a fala sai como veio.
  def sem_cotacao_viva?
    return false if @conversa.blank?

    !::Autonomia::Agents::ToolRun.for_conversation(@conversa)
                                 .where(slug: ::Autonomia::Insurance::ResultadoDaCotacao.cotacao.slug)
                                 .active.exists?
  end

  # A cotação que corria no começo do turno parou de correr, e não por ter sido trocada ou descartada (um pedido
  # novo no turno troca a execução, e aí a nova é que corre).
  def fechou_no_turno?
    return false if @cotacao_no_inicio.nil?

    run = leitura_final.run
    ::Autonomia::Insurance::ResultadoDaCotacao::FORA.exclude?(run.status) && !leitura_final.correndo?
  end

  def leitura_final
    @leitura_final ||= ::Autonomia::Insurance::ResultadoDaCotacao.new(@cotacao_no_inicio.reload)
  end
end
