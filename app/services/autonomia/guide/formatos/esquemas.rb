# A regra interna das colunas JSON, lida do esquema que o próprio modelo declara (#932).
#
# Qualquer modelo com `validates :coluna, json_schema: { schema: ... }` entra sozinho no formato da
# ação: o gerador pega o esquema daqui, a conferência valida o corpo contra ele e confere os ids
# marcados `x-da-conta` na conta de quem pede. Nada aqui conhece um modelo pelo nome; o que o esquema
# diz é tudo o que o Guia sabe.
#
# Anotações que o validador ignora e o Guia lê:
# - `x-da-conta: { modelo, campo }`: o valor tem de existir na conta (por padrão, o id do modelo);
# - `x-sem-volta: true`: o corpo que cai neste nó faz algo sem desfazer, e a pessoa confirma antes;
# - `x-quando: { campo: valor }`: este ramo vale quando o objeto vizinho tem aquele valor;
# - `description`: o que o motor faz de verdade, em português.
module Autonomia::Guide::Formatos::Esquemas
  ALTERNATIVAS = %w[anyOf oneOf].freeze

  module_function

  # O esquema geral da coluna (sem registro), ou nil quando ela não declara um.
  def da_coluna(modelo, nome)
    validador = modelo&.validators_on(nome.to_sym)&.grep(JsonSchemaValidator)&.first
    validador&.esquema
  end

  def validador(esquema)
    JSONSchemer.schema(esquema, formats: JsonSchemaFormatos::TODOS)
  end

  # O dado cabe no trecho do esquema? As anotações não contam.
  def cabe?(trecho, valor)
    validador(trecho.reject { |chave, _| chave.start_with?('x-') }).valid?(valor)
  end

  # Cada trecho do esquema que o dado alcança, com o ponteiro do dado: [ponteiro, trecho, valor].
  # O ramo `then` só entra quando o `if` casa, e de `anyOf`/`oneOf` só a primeira opção em que o dado
  # cabe, como na validação: "inbox_id" cabe na lista fechada e não é atributo personalizado.
  def percorrer(esquema, valor, ponteiro = '', &)
    return unless esquema.is_a?(Hash)

    yield ponteiro, esquema, valor
    combinados(esquema, valor).each { |sub| percorrer(sub, valor, ponteiro, &) }
    percorrer_objeto(esquema, valor, ponteiro, &) if valor.is_a?(Hash)
    percorrer_lista(esquema['items'], valor, ponteiro, &) if valor.is_a?(Array)
  end

  # Os trechos que valem para o mesmo dado: todo o allOf, a primeira opção de anyOf/oneOf em que ele
  # cabe (sem nenhuma, todas) e o then do if que casa.
  def combinados(esquema, valor)
    alternativas = ALTERNATIVAS.flat_map do |chave|
      opcoes = Array(esquema[chave])
      cabe = opcoes.find { |opcao| opcao.is_a?(Hash) && cabe?(opcao, valor) }
      cabe ? [cabe] : opcoes
    end
    entao = esquema['if'] && validador(esquema['if']).valid?(valor) ? [esquema['then']] : []
    [*Array(esquema['allOf']), *alternativas, *entao]
  end

  def percorrer_objeto(esquema, valor, ponteiro, &)
    propriedades = esquema['properties'] || {}
    valor.each do |chave, item|
      sub = propriedades.fetch(chave) { esquema['additionalProperties'] }
      percorrer(sub, item, "#{ponteiro}/#{chave}", &)
    end
  end

  def percorrer_lista(itens, valor, ponteiro, &)
    valor.each_with_index do |item, indice|
      sub = itens.is_a?(Array) ? itens[indice] : itens
      percorrer(sub, item, "#{ponteiro}/#{indice}", &)
    end
  end

  # O dado cai em algum trecho marcado `x-sem-volta`? Trecho com `if` vale quando o `if` casa.
  def sem_volta?(esquema, valor)
    percorrer(esquema, valor) do |_ponteiro, trecho, dado|
      next unless trecho['x-sem-volta']
      return true if trecho['if'] ? validador(trecho['if']).valid?(dado) : cabe?(trecho, dado)
    end
    false
  end

  # O ramo que um valor fixo identifica: o trecho cujo `if` fixa um campo nele (com `then`), ou o que
  # tem `x-quando` com ele. 'send_email_to_team' acha o ramo da ação; 'move_stage', o do tipo de passo.
  def ramo(esquema, nome)
    ramos(esquema).find { |valor, _ramo| valor == nome }&.last
  end

  # [valor, ramo] de cada ramo do esquema, na ordem em que aparecem.
  def ramos(esquema)
    lista = []
    visitar(esquema) do |trecho|
      _campo, valor = do_ramo(trecho)
      lista << [valor, trecho] unless valor.nil?
    end
    lista
  end

  # [campo, valor] que identificam o ramo, ou nil se o trecho não é ramo.
  def do_ramo(trecho)
    return trecho['x-quando']&.first unless trecho['then']

    trecho.dig('if', 'properties')&.find { |_campo, fixo| fixo.is_a?(Hash) && fixo.key?('const') }&.then { |campo, fixo| [campo, fixo['const']] }
  end

  def visitar(trecho, &)
    case trecho
    when Hash
      yield trecho
      trecho.each_value { |valor| visitar(valor, &) }
    when Array then trecho.each { |item| visitar(item, &) }
    end
  end

  # O tipo do campo pelo esquema, no vocabulário do formato.
  def tipo(esquema)
    tipos = Array(esquema['type'].presence || Array(esquema['anyOf']).pluck('type').uniq)
    return 'lista_de_objetos' if tipos.include?('array') && Array(esquema.dig('items', 'type')).include?('object')
    return 'lista' if tipos.include?('array')

    'objeto' if tipos.include?('object')
  end
end
