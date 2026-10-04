# A conferência DENTRO dos campos JSON do corpo (#932): o que vai em `actions`, `conditions`,
# `action_config` e em qualquer coluna que declare esquema.
#
# A conferência do primeiro nível (`Conferencia`) não via aqui dentro, e era aqui que o Guia errava em
# silêncio: chave que o motor não lê, id em texto, time de outra conta. Agora cada campo com esquema é
# validado contra ele, e cada valor marcado `x-da-conta` é procurado na conta de quem pede. A recusa
# traz o caminho exato no corpo (`/actions/0/action_params/0`), o motivo e, quando há, os válidos.
#
# Os campos de dentro sem esquema (o `action_type` de um passo) só têm a lista fechada conferida.
class Autonomia::Guide::Formatos::PorDentro
  Esquemas = ::Autonomia::Guide::Formatos::Esquemas
  MAX_VALIDOS = 20
  TIPOS = { 'integer' => 'número inteiro, sem aspas', 'string' => 'texto', 'array' => 'lista', 'object' => 'objeto',
            'boolean' => 'true ou false', 'number' => 'número', 'null' => 'nulo' }.freeze
  FORMATOS = { 'uri' => 'endereço http(s) completo', 'email' => 'e-mail',
               JsonSchemaFormatos::LISTA_DE_EMAILS => 'e-mails separados por vírgula ({{contact.email}} vale o do cliente)' }.freeze
  ROTULOS = %w[name title attribute_display_name].freeze

  def initialize(campos, valores, conta:)
    @campos = campos
    @valores = valores
    @conta = conta
  end

  # [{ caminho:, motivo:, validos: }]
  def problemas
    @problemas ||= conferir_nivel(@campos, @valores, '', raiz: true).uniq
  end

  def sem_volta?
    cada_campo(@campos, @valores, '').any? { |campo, valor, _ponteiro| Esquemas.sem_volta?(campo['esquema'], valor) }
  end

  private

  # Cada campo com esquema que o corpo traz, descendo nos objetos e listas sem esquema.
  def cada_campo(campos, valores, ponteiro, &bloco)
    return enum_for(:cada_campo, campos, valores, ponteiro) unless bloco
    return unless valores.is_a?(Hash)

    valores.each do |nome, valor|
      campo = campos[nome]
      next unless campo.is_a?(Hash)

      caminho = "#{ponteiro}/#{nome}"
      next yield(campo.merge('esquema' => do_vizinho(campo['esquema'], valores)), valor, caminho) if campo['esquema']

      descer(campo, valor, caminho) { |*achado| yield(*achado) }
    end
  end

  def descer(campo, valor, caminho, &)
    return unless campo['campos']

    return cada_campo(campo['campos'], valor, caminho, &) if valor.is_a?(Hash)

    Array(valor).each_with_index { |item, indice| cada_campo(campo['campos'], item, "#{caminho}/#{indice}", &) } if valor.is_a?(Array)
  end

  def conferir_nivel(campos, valores, ponteiro, raiz: false)
    return [] unless valores.is_a?(Hash)

    valores.flat_map do |nome, valor|
      campo = campos[nome]
      next [] unless campo.is_a?(Hash)

      conferir_campo(campo.merge('esquema' => do_vizinho(campo['esquema'], valores)).compact, valor, "#{ponteiro}/#{nome}", raiz)
    end
  end

  # O esquema que depende de um campo vizinho (`x-quando`, como o action_config pelo action_type)
  # vale só no ramo do valor que o corpo traz. Sem vizinho que case, vale o esquema inteiro.
  def do_vizinho(esquema, vizinhos)
    return esquema unless esquema.is_a?(Hash) && esquema['anyOf']

    esquema['anyOf'].find { |ramo| ramo['x-quando']&.all? { |campo, valor| vizinhos[campo].to_s == valor.to_s } } || esquema
  end

  def conferir_campo(campo, valor, caminho, raiz)
    return [*pelo_esquema(campo['esquema'], valor, caminho), *da_conta(campo['esquema'], valor, caminho)] if campo['esquema']

    [*(raiz ? [] : fora_da_lista(campo, valor, caminho)), *dentro(campo, valor, caminho)]
  end

  def dentro(campo, valor, caminho)
    return [] unless campo['campos']
    return conferir_nivel(campo['campos'], valor, caminho) if valor.is_a?(Hash)
    return [] unless valor.is_a?(Array)

    valor.each_with_index.flat_map { |item, indice| conferir_nivel(campo['campos'], item, "#{caminho}/#{indice}") }
  end

  def fora_da_lista(campo, valor, caminho)
    lista = Array(campo['um_de']).map(&:to_s)
    return [] if lista.empty? || campo['valida_no_servidor'] || valor.nil? || lista.include?(valor.to_s)

    [{ caminho: caminho, motivo: "#{valor.to_json} não é um valor aceito", validos: lista }]
  end

  def pelo_esquema(esquema, valor, caminho)
    Esquemas.validador(esquema).validate(valor).map do |erro|
      motivo, validos = explicar(erro)
      { caminho: "#{caminho}#{erro['data_pointer']}", motivo: com_descricao(motivo, erro['schema']), validos: validos }.compact
    end
  end

  def explicar(erro)
    trecho = erro['schema'].is_a?(Hash) ? erro['schema'] : {}
    case erro['type']
    when 'enum' then ["#{erro['data'].to_json} não vale aqui", trecho['enum']]
    when 'const' then ["tem de ser #{trecho['const'].to_json}", nil]
    when 'required' then ["falta #{erro.dig('details', 'missing_keys').join(', ')}", nil]
    when 'schema' then ['chave que esta regra não conhece: a plataforma a recusaria', vizinhas(erro)]
    when 'format' then ["não é #{FORMATOS.fetch(trecho['format'], trecho['format'])}", nil]
    else [explicar_forma(erro, trecho), nil]
    end
  end

  def explicar_forma(erro, trecho)
    case erro['type']
    when 'minItems' then "precisa de pelo menos #{trecho['minItems']} item(ns)"
    when 'maxItems' then "aceita no máximo #{trecho['maxItems']} item(ns)"
    when 'minLength' then 'não pode ficar vazio'
    when 'type' then "tem de ser #{Array(trecho['type']).map { |tipo| TIPOS.fetch(tipo, tipo) }.join(' ou ')}"
    else TIPOS.key?(erro['type']) ? "tem de ser #{TIPOS[erro['type']]}" : "não bate com a regra (#{erro['type']})"
    end
  end

  def com_descricao(motivo, trecho)
    descricao = trecho.is_a?(Hash) ? trecho['description'] : nil
    descricao ? "#{motivo} — #{descricao}" : motivo
  end

  # As chaves que o objeto aceita, para a chave desconhecida: lidas do nó pai no esquema.
  def vizinhas(erro)
    partes = erro['schema_pointer'].to_s.split('/').drop(1)
    return unless partes.last == 'additionalProperties'

    pai = partes[0...-1].reduce(erro['root_schema']) { |trecho, parte| trecho.is_a?(Array) ? trecho[parte.to_i] : trecho&.dig(parte) }
    pai.is_a?(Hash) ? pai['properties']&.keys : nil
  end

  def da_conta(esquema, valor, caminho)
    return [] unless @conta

    problemas = []
    Esquemas.percorrer(esquema, valor) do |ponteiro, trecho, dado|
      next unless trecho['x-da-conta'] && !dado.nil? && Esquemas.cabe?(trecho, dado)

      problema = fora_da_conta(trecho, dado, "#{caminho}#{ponteiro}")
      problemas << problema if problema
    end
    problemas.uniq
  end

  def fora_da_conta(trecho, dado, caminho)
    modelo = trecho.dig('x-da-conta', 'modelo').safe_constantize
    escopo = modelo && escopo_da_conta(modelo)
    return unless escopo

    campo = trecho.dig('x-da-conta', 'campo') || modelo.primary_key
    return if escopo.exists?(campo => dado)

    { caminho: caminho, motivo: "#{dado.to_json} não existe nesta conta (#{modelo.model_name.human})", validos: validos(escopo, campo) }
  end

  # Os registros da conta: pela associação da conta com esse modelo, ou pelo account_id.
  def escopo_da_conta(modelo)
    associacoes = @conta.class.reflect_on_all_associations(:has_many).select { |assoc| classe(assoc) == modelo }
    associacao = associacoes.find { |assoc| assoc.name.to_s == modelo.model_name.plural } || associacoes.first
    return @conta.public_send(associacao.name) if associacao

    modelo.where(account_id: @conta.id) if modelo.column_names.include?('account_id')
  end

  def classe(associacao)
    associacao.klass
  rescue NameError, ArgumentError
    nil
  end

  def validos(escopo, campo)
    rotulo = (ROTULOS & escopo.klass.column_names).find { |coluna| coluna != campo }
    linhas = escopo.limit(MAX_VALIDOS).pluck(*[campo, rotulo].compact)
    linhas.map { |linha| linha.is_a?(Array) ? "#{linha.first} (#{linha.last})" : linha.to_s }
  end
end
