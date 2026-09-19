# A FALA DA LIA NÃO PROMETE PARA DEPOIS NEM CONTRADIZ A COTAÇÃO QUE FECHOU NO TURNO (#510 e #511, parte do #420).
#
# Os dois defeitos têm a mesma forma: a fala sai dizendo algo que o estado do turno desmente.
#
#   - #510: ela promete consultar ou confirmar DEPOIS, e nenhuma ferramenta rodou no turno. Não existe turno
#     seguinte sem mensagem nova do cliente, então a promessa fica pendurada.
#   - #511: ela diz que a cotação continua correndo, e a cotação que corria no começo do turno fechou antes de a
#     fala sair. O modelo leu o estado antigo.
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

  # -> a execução de `cotar_seguro` que corre agora na conversa, ou nil. Lida no começo do turno, antes do modelo.
  def self.cotacao_correndo(conversation_id)
    leitura = ::Autonomia::Insurance::ResultadoDaCotacao.da_conversa(conversation_id)
    leitura&.correndo? ? leitura.run : nil
  end

  def initialize(cotacao_no_inicio:)
    @cotacao_no_inicio = cotacao_no_inicio
  end

  # -> os sinais que a fala dispara (`:promessa`, `:cotacao_fechada`); vazio quando ela pode sair como está.
  # Com escalada a promessa não fica pendurada: quem segue é o atendente.
  def sinais(reply, ferramentas_no_turno:, escalou: false)
    texto = reply.to_s
    promessa = !escalou && ferramentas_no_turno.zero? && casa?(texto, PROMESSA)
    fechada = casa?(texto, AINDA_CORRENDO) && fechou_no_turno?
    [(:promessa if promessa), (:cotacao_fechada if fechada)].compact
  end

  # -> o pedido de reescrita ao modelo para estes sinais.
  def pedido(sinais)
    partes = []
    partes << pedido_da_promessa if sinais.include?(:promessa)
    partes << pedido_da_cotacao if sinais.include?(:cotacao_fechada)
    (partes + ['Reescreva a resposta ao cliente em reply, mantendo o resto do que ela diz. Sem travessão.']).join("\n\n")
  end

  private

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
