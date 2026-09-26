# O QUE O ESPECIALISTA DE COTAÇÃO DEVOLVE À LIA: FATOS, NÃO FALA (item 9 da auditoria de voz, 26/09/2026).
#
# Até aqui ele devolvia "texto pronto, que o principal vai parafrasear" (`Specialists::Runner::RESULT_SCHEMA`). Quem
# conhecia o caso escrevia uma frase para a Lia, e a Lia, que fala com a pessoa, reescrevia sem o contexto: um
# telefone sem fio, e a voz saía genérica. Agora ele devolve o que fez e sabe, em partes separadas, e quem escreve a
# fala é ela, reagindo ao que a pessoa disse.
#
# SÓ PARA OS ESPECIALISTAS QUE A AUTONOM.IA MANTÉM (`QuoteAgent::Builder.ramo_do_especialista`). O `Runner` serve a
# qualquer especialista (#311), e o de fora da cotação continua com a prosa de sempre.
#
# O QUE NÃO MUDA: o dado que falta sai com o nome que o especialista escreveu, na linha "Ainda falta:"; o preço, a
# conferência dos preços e a da fala continuam sobre a fala da Lia (`Answerer`), e a SITUAÇÃO DA COTAÇÃO continua
# sendo acrescentada pelo `Runner` depois destes fatos.
module Autonomia::Insurance::QuoteAgent::RetornoDoEspecialista
  TEXTO = { type: 'string' }.freeze
  LISTA = { type: 'array', items: TEXTO }.freeze

  def self.lista_de(campos)
    { type: 'array', items: { type: 'object', properties: campos.index_with { TEXTO }, required: campos,
                              additionalProperties: false } }
  end

  # Em `strict`, todo campo é obrigatório: o que não houver vai vazio (texto vazio, lista vazia).
  SCHEMA = {
    name: 'autonomia_fatos_do_especialista',
    schema: {
      type: 'object',
      properties: {
        o_que_fez: TEXTO.merge(description: 'O que você fez neste turno e o que trocou, em frases simples. Vazio se nada.'),
        resultado_lido: TEXTO.merge(description: 'O que a leitura do resultado devolveu e a pessoa pediu: seguradora, ' \
                                                 'valor e período exatamente como vieram. Vazio se não leu.'),
        pedido_que_entrou: LISTA.merge(description: 'O que foi pedido às seguradoras a partir do que a pessoa pediu.'),
        pedido_que_nao_coube: lista_de(%w[pedido motivo]).merge(description: 'O que ela pediu e não coube, com o motivo ' \
                                                                             'em linguagem de gente.'),
        falta_perguntar: lista_de(%w[dado por_que]).merge(description: 'O que falta perguntar à pessoa, e por quê.'),
        contexto_da_pessoa: LISTA.merge(description: 'O que a pessoa revelou de si e do pedido: urgência, preocupação, ' \
                                                     'para quem é.')
      },
      required: %w[o_que_fez resultado_lido pedido_que_entrou pedido_que_nao_coube falta_perguntar contexto_da_pessoa],
      additionalProperties: false
    }
  }.freeze

  # O que a Lia lê antes dos fatos: de quem são, e que a fala é dela.
  CABECALHO = 'FATOS DO ESPECIALISTA. Nada aqui é frase para a pessoa: é o que ele fez e sabe, para você escrever a ' \
              'sua fala.'.freeze
  # A linha do que falta começa sempre assim, com o dado como o especialista o escreveu. É ela que a §4.2 e a §5 do
  # manual da Lia chamam de "o especialista disser que falta um dado".
  AINDA_FALTA = 'Ainda falta:'.freeze

  module_function

  # -> o especialista é um dos que a Autonom.ia mantém? Só eles devolvem fatos.
  def aplica?(specialist)
    ::Autonomia::Insurance::QuoteAgent::Builder.ramo_do_especialista(specialist).present?
  end

  # -> o texto que vai à Lia, ou nil quando o especialista não devolveu nada.
  def texto(parsed)
    linhas = [
      linha('O que ele fez:', parsed['o_que_fez']),
      linha('Resultado lido da cotação:', parsed['resultado_lido']),
      linha('Pedido às seguradoras, a partir do que a pessoa pediu:', itens(parsed['pedido_que_entrou'])),
      linha('Do pedido da pessoa, não coube:', pares(parsed['pedido_que_nao_coube'], 'pedido', 'motivo')),
      linha(AINDA_FALTA, pares(parsed['falta_perguntar'], 'dado', 'por_que')),
      linha('O que a pessoa contou de si e do pedido:', itens(parsed['contexto_da_pessoa']))
    ].compact
    linhas.empty? ? nil : [CABECALHO, *linhas].join("\n")
  end

  def linha(rotulo, valor)
    valor = valor.to_s.strip
    valor.empty? ? nil : "#{rotulo} #{valor}"
  end

  # O ponto final de cada parte sai: as partes se juntam com ponto e vírgula, e a linha termina com um ponto só.
  def itens(lista)
    textos = Array(lista).map { |item| sem_ponto(item) }.reject(&:empty?)
    textos.empty? ? nil : "#{textos.join('; ')}."
  end

  # Cada par é "o que (motivo)"; sem motivo, só o que. O "o que" sai como veio, só sem o ponto final.
  def pares(lista, chave, motivo)
    textos = Array(lista).filter_map do |item|
      next unless item.is_a?(Hash)

      nome = sem_ponto(item[chave])
      next if nome.empty?

      porque = sem_ponto(item[motivo])
      porque.empty? ? nome : "#{nome} (#{porque})"
    end
    textos.empty? ? nil : "#{textos.join('; ')}."
  end

  def sem_ponto(texto)
    texto.to_s.strip.delete_suffix('.').strip
  end
end
