# Descer num esquema que se monta por referências (`$ref` para `definitions`), como a receita da Automação livre
# (#2889). O resumo de um campo (`ResumoDoEsquema`) mostra o primeiro nível; aqui o Guia pede um pedaço pelo caminho, e
# cada passo do caminho é, nesta ordem: uma chave do objeto, a opção de uma lista de alternativas pelo valor fixo que a
# identifica (o `tipo` de um passo: "passos.mensagem"; o valor pode ter ponto, "gatilho.tipo" não, mas "card.criado"
# sim) ou uma definição pelo nome ("condicao", "valor"). Lista desce sozinha para o item.
#
# O que volta é texto curto: o objeto vira uma linha por chave, a lista de alternativas vira uma linha por opção, e o
# resto vai em JSON com as referências pelo nome, para o Guia pedir a próxima. Sem `$ref` no esquema, nada aqui é usado.
class Autonomia::Guide::Formatos::NavegacaoDoEsquema
  # Maior que o teto do resumo da ação (2500): é o pedaço que o Guia pediu, e a descrição de um campo da receita passa
  # de 5 mil caracteres (os gatilhos).
  TETO = 6000
  DESCRICAO_NA_LISTA = 300
  ALTERNATIVAS = %w[oneOf anyOf].freeze

  def initialize(caminho, esquema)
    @caminho = caminho
    @esquema = esquema
  end

  def referencias? = @esquema.is_a?(Hash) && @esquema['definitions'].is_a?(Hash)

  # O pedaço do esquema no caminho ("passos.mensagem"), ou nil se o caminho não existe.
  def texto(nome)
    trecho = andar(nome.to_s.split('.'))
    return unless trecho

    cortar(descrever("#{@caminho}.#{nome}", trecho))
  end

  # A linha que o resumo do campo ganha: por onde descer.
  def dica
    chaves = (@esquema['properties'] || {}).keys
    exemplos = chaves.map { |chave| "\"#{@caminho}.#{chave}\"" }.join(', ')
    "Para o detalhe, peça formato_da_acao com campo #{exemplos} (e desça: \"#{@caminho}.<chave>.<valor do tipo>\"). " \
      "Partes que se repetem: #{@esquema['definitions'].keys.join(', ')} (peça \"#{@caminho}.<nome>\")."
  end

  private

  def andar(partes)
    atual = @esquema
    indice = 0
    while indice < partes.size
      atual, indice = proximo(resolver(atual), partes, indice)
      return unless atual
    end
    resolver(atual)
  end

  # O pedaço mais longo do caminho que casa vale primeiro: "card.criado" é um valor só.
  def proximo(atual, partes, indice)
    partes.size.downto(indice + 1) do |fim|
      filho = filho(atual, partes[indice...fim].join('.'))
      return [filho, fim] if filho
    end
    [nil, indice]
  end

  def filho(atual, nome)
    alvo = item(atual)
    return unless alvo.is_a?(Hash)

    alvo.dig('properties', nome) || variante(alvo, nome) || @esquema.dig('definitions', nome)
  end

  def resolver(trecho)
    visto = Set.new
    trecho = definicao(trecho['$ref']) while trecho.is_a?(Hash) && trecho['$ref'].is_a?(String) && visto.add?(trecho['$ref'])
    trecho
  end

  def definicao(referencia)
    return unless referencia.start_with?('#/')

    referencia.delete_prefix('#/').split('/').reduce(@esquema) { |nivel, parte| nivel.is_a?(Hash) ? nivel[parte] : nil }
  end

  def item(trecho)
    trecho = resolver(trecho)
    trecho.is_a?(Hash) && trecho['type'] == 'array' && trecho['items'].is_a?(Hash) ? resolver(trecho['items']) : trecho
  end

  def opcoes(trecho)
    ALTERNATIVAS.flat_map { |chave| Array(trecho[chave]) }.map { |opcao| resolver(opcao) }.select { |opcao| opcao.is_a?(Hash) }
  end

  # A opção que fixa uma chave no valor pedido: { "tipo": { "const": "mensagem" } }.
  def variante(trecho, nome)
    opcoes(trecho).find { |opcao| fixo(opcao)&.last == nome }
  end

  def fixo(opcao)
    (opcao['properties'] || {}).each { |campo, regra| return [campo, regra['const']] if regra.is_a?(Hash) && regra.key?('const') }
    nil
  end

  def descrever(caminho, trecho)
    proprio = resolver(trecho)
    alvo = item(proprio)
    lista = !alvo.equal?(proprio)
    cabeca = ["Campo #{caminho}#{' (lista; cada item:)' if lista}", proprio['description'], (alvo['description'] if lista)]
    [*cabeca, *corpo(caminho, alvo), *referencias(alvo)].compact.join("\n")
  end

  def corpo(caminho, alvo)
    return alternativas(caminho, alvo) if opcoes(alvo).any? { |opcao| fixo(opcao) }
    return chaves(alvo) if alvo['properties']

    [JSON.pretty_generate(alvo.except('description'))]
  end

  def alternativas(caminho, alvo)
    linhas = opcoes(alvo).map do |opcao|
      campo, valor = fixo(opcao)
      next "- outra forma: #{JSON.generate(opcao).first(DESCRICAO_NA_LISTA)}" unless campo

      obrigatorias = Array(opcao['required']) - [campo]
      "- #{campo} = #{valor}#{" (exige #{obrigatorias.join(', ')})" if obrigatorias.any?}#{resumo(opcao['description'])}"
    end
    ["Um destes (peça \"#{caminho}.<valor>\" para o formato de cada um):", *linhas]
  end

  def chaves(alvo)
    obrigatorias = Array(alvo['required'])
    linhas = alvo['properties'].map do |nome, regra|
      resolvida = resolver(regra) || {}
      "- #{nome} (#{tipo(regra, resolvida)}#{', obrigatório' if obrigatorias.include?(nome)})#{valores(resolvida)}" \
        "#{resumo(resolvida['description'])}"
    end
    ['Chaves:', *linhas, *("Também: #{alvo.except('properties', 'description').keys.join(', ')}." if extras?(alvo))]
  end

  def extras?(alvo) = alvo.except('properties', 'description', 'type', 'additionalProperties', 'required').any?

  def tipo(regra, resolvida)
    nome = regra['$ref'].to_s.split('/').last
    base = Array(resolvida['type']).join(' ou ').presence || (opcoes(resolvida).any? ? 'uma das formas' : 'valor')
    nome.present? ? "#{base}, ver #{nome}" : base
  end

  def valores(resolvida)
    lista = Array(resolvida['enum']) + Array(resolvida.slice('const').values)
    lista.any? ? "; um de: #{lista.join(', ')}" : ''
  end

  def resumo(descricao)
    descricao.present? ? ": #{descricao.first(DESCRICAO_NA_LISTA)}#{'…' if descricao.size > DESCRICAO_NA_LISTA}" : ''
  end

  # As definições que o pedaço cita, para o Guia saber o que pedir em seguida.
  def referencias(alvo)
    nomes = citadas(alvo).filter_map { |referencia| referencia.delete_prefix('#/definitions/') if referencia.start_with?('#/definitions/') }.uniq
    nomes.any? ? ["Partes citadas: #{nomes.join(', ')} (peça \"#{@caminho}.<nome>\")."] : []
  end

  def citadas(trecho)
    case trecho
    when Hash then [*(trecho['$ref'] if trecho['$ref'].is_a?(String)), *trecho.values.flat_map { |valor| citadas(valor) }]
    when Array then trecho.flat_map { |valor| citadas(valor) }
    else []
    end
  end

  def cortar(texto)
    texto.size > TETO ? "#{texto.first(TETO)}\n(cortado pelo limite de tamanho; peça um pedaço menor)" : texto
  end
end
