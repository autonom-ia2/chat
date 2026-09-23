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
# O QUE A FALA DIZ, QUEM DECLARA É A PRÓPRIA LIA (23/09/2026). Até aqui eram listas de regex, e a regra do Rodrigo
# proíbe interpretar linguagem com lista de palavra. Na mesma resposta em que escreve ao cliente, ela marca quatro
# sim ou não sobre o que escreveu (`leitura_da_fala`, no `SCHEMA_DA_RESPOSTA`), sem chamada nem agente a mais. Este
# arquivo só cruza a declaração com o ESTADO do turno: se alguma ferramenta rodou, se há cotação viva, se a que
# corria fechou (o que ela não tem como saber enquanto escreve). Quem reescreve é o modelo, uma vez, com as
# ferramentas do turno à mão (o `Answerer`).
class Autonomia::Agents::ConferenciaDaFala
  # As perguntas que a Lia responde sobre a própria fala. A descrição de cada campo é a pergunta: "não" é sempre
  # uma resposta possível.
  PERGUNTAS = {
    'promete_verificar_depois' =>
      'Sua mensagem promete consultar, verificar, confirmar ou responder algo DEPOIS, em vez de responder agora? ' \
      'Não conta dizer que o resultado de uma cotação já em andamento chega depois.',
    'diz_que_cotacao_ainda_corre' =>
      'Sua mensagem diz que a cotação ainda está em andamento, ou que o comparativo ou o resultado dela ainda vai chegar?',
    'promete_cotacao_ou_comparativo' =>
      'Sua mensagem diz que vai cotar, ou que opções, preços, comparativo ou resultado de cotação vão chegar ao cliente?',
    'mostra_engrenagem' =>
      'Sua mensagem mostra ao cliente a engrenagem interna do atendimento: especialista, fluxo, prompt, ferramenta ou ' \
      'agente como parte do atendimento, ou o "nosso sistema"? Não conta o que é do mundo do cliente (o sistema da ' \
      'seguradora, sistema de alarme ou rastreamento, ferramenta de trabalho, agente autorizado, o modelo do carro), ' \
      'nem se apresentar como assistente virtual ou IA.'
  }.freeze

  # O schema da resposta do agente de cotação: o de todo agente mais a declaração sobre a fala. Os outros agentes
  # seguem com o `PromptBuilder::ANSWER_SCHEMA`.
  SCHEMA_DA_RESPOSTA = begin
    base = ::Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA
    leitura = { type: 'object', additionalProperties: false, required: PERGUNTAS.keys,
                description: 'Sobre a mensagem que você escreveu em reply: responda com sim ou não, pelo sentido.',
                properties: PERGUNTAS.transform_values { |pergunta| { type: 'boolean', description: pergunta } } }
    { name: 'autonomia_agent_answer_cotacao',
      schema: base[:schema].merge(properties: base[:schema][:properties].merge(leitura_da_fala: leitura),
                                  required: base[:schema][:required] + ['leitura_da_fala']) }.freeze
  end

  def initialize(conversa:, cotacao_no_inicio:)
    @conversa = conversa
    @cotacao_no_inicio = cotacao_no_inicio
  end

  # -> os sinais que a fala dispara (`:promessa`, `:cotacao_fechada`, `:cotacao_prometida`,
  # `:vocabulario_interno`); vazio quando ela pode sair como está. `leitura` é a declaração da Lia sobre a fala
  # (`leitura_da_fala` da resposta); sem ela, nenhum sinal sai.
  # Com escalada a promessa não fica pendurada: quem segue é o atendente. Vale para as duas promessas, pela
  # mesma razão. O vocabulário não: é justamente ao escalar que "o especialista" escapa.
  def sinais(leitura, ferramentas_no_turno:, escalou: false)
    leitura = leitura.to_h
    fechada = leitura['diz_que_cotacao_ainda_corre'] == true && fechou_no_turno?
    [(:promessa if promessa?(leitura, ferramentas_no_turno, escalou)),
     (:cotacao_fechada if fechada),
     (:cotacao_prometida if prometida?(leitura, escalou, fechada)),
     (:vocabulario_interno if leitura['mostra_engrenagem'] == true)].compact
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

  # -> a execução de `cotar_seguro` que corre agora na conversa, de qualquer produto, ou nil. Lida no começo do
  # turno, antes do modelo.
  def self.cotacao_correndo(conversation_id)
    ::Autonomia::Insurance::ResultadoDaCotacao.correndo_na_conversa(conversation_id)&.run
  end

  private

  # #510: promete consultar depois e nenhuma ferramenta rodou no turno.
  # A promessa sobre uma cotação que CORRE não fica pendurada: o resultado chega sozinho (revisão de 23/09/2026).
  # Sem esta guarda, "te mando o comparativo assim que sair" pedia reescrita, e a reescrita podia cotar de novo e
  # trocar a cotação que já corria.
  def promessa?(leitura, ferramentas_no_turno, escalou)
    return false if escalou || !ferramentas_no_turno.zero? || leitura['promete_verificar_depois'] != true

    sobre_a_cotacao = leitura['promete_cotacao_ou_comparativo'] == true || leitura['diz_que_cotacao_ainda_corre'] == true
    !(sobre_a_cotacao && !sem_cotacao_viva?)
  end

  # #547: promete a cotação ou o comparativo e não há cotação nenhuma viva. A que fechou neste turno já é
  # `:cotacao_fechada`, que diz outra coisa ao modelo; os dois sinais nunca saem juntos.
  def prometida?(leitura, escalou, fechada)
    promete = leitura['promete_cotacao_ou_comparativo'] == true || leitura['diz_que_cotacao_ainda_corre'] == true
    !escalou && !fechada && promete && sem_cotacao_viva? && !fechou_no_turno?
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
  # Com outra cotação da conversa ainda correndo (auto e residencial juntos), "ainda está saindo" pode ser dela: o
  # sinal não sai, para não mandar a Lia dizer que o outro seguro terminou (revisão da chat#608).
  def fechou_no_turno?
    return false if @cotacao_no_inicio.nil?
    return false if ::Autonomia::Insurance::ResultadoDaCotacao.correndo_na_conversa(@conversa).present?

    run = leitura_final.run
    ::Autonomia::Insurance::ResultadoDaCotacao::FORA.exclude?(run.status) && !leitura_final.correndo?
  end

  def leitura_final
    @leitura_final ||= ::Autonomia::Insurance::ResultadoDaCotacao.new(@cotacao_no_inicio.reload)
  end
end
