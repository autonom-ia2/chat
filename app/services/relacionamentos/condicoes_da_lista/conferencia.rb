# #3168 — confere as linhas de "Por outra informação" (Relacionamentos::CondicoesDaLista) antes de irem para o filtro da
# lista de contatos de hoje, que confia na tela dele. Cada linha precisa de:
# - informação (`attribute_key`) em texto; a que não existe o próprio filtro recusa, e o campo da conta de um tipo que
#   o filtro não sabe comparar (moeda, porcentagem, pessoa, contato) também sai;
# - "como" (`filter_operator`) conhecido e, num campo da conta, um que o tipo dele tem (o filtro só confere os campos
#   padrão, pelo filter_keys.yml);
# - valores numa lista: sim/não (Bloqueada, campo da conta de marcar) com um true ou false; o resto em texto, e lista
#   vazia só em "está preenchido"/"está vazio";
# - ligação ("and"/"or") em toda linha menos a última, que vai sem.
# O que falta vira Relacionamentos::PedidoInvalido (422).
class Relacionamentos::CondicoesDaLista::Conferencia
  MAXIMO = 20
  MAXIMO_DE_VALORES = 50
  SEM_VALOR = %w[is_present is_not_present].freeze
  IGUALDADE = %w[equal_to not_equal_to].freeze
  COMPARACAO = %w[is_greater_than is_less_than].freeze
  # O que cada tipo de campo da conta aceita (os tipos de FilterService::ATTRIBUTE_TYPES).
  COMO_DO_TIPO = {
    'text' => IGUALDADE + %w[contains does_not_contain] + SEM_VALOR,
    'numeric' => IGUALDADE + COMPARACAO + SEM_VALOR,
    'date' => IGUALDADE + COMPARACAO + %w[days_before] + SEM_VALOR,
    'boolean' => IGUALDADE
  }.freeze
  CONHECIDOS = COMO_DO_TIPO.values.flatten.uniq.freeze
  LIGACOES = %w[and or].freeze

  attr_reader :linhas

  def initialize(account, texto)
    @account = account
    lidas = ler(texto)
    @linhas = lidas.each_with_index.map { |linha, indice| conferida(linha, ultima: indice == lidas.size - 1) }
  end

  private

  def ler(texto)
    lidas = JSON.parse(texto.to_s)
    recusar('em formato inválido') unless lidas.is_a?(Array) && lidas.all?(Hash)
    recusar("de 1 a #{MAXIMO} linhas") unless lidas.size.between?(1, MAXIMO)

    lidas
  rescue JSON::ParserError
    recusar('em formato inválido')
  end

  def conferida(linha, ultima:)
    linha = linha.with_indifferent_access
    chave = linha[:attribute_key]
    recusar('linha sem informação') unless chave.is_a?(String) && chave.present?

    como = linha[:filter_operator]
    recusar("#{chave}: \"como\" desconhecido") unless CONHECIDOS.include?(como)

    conferir_ligacao(chave, linha[:query_operator], ultima)
    tipo = tipo_da_conta(chave)
    recusar("#{chave}: \"como\" que o campo não tem") if tipo && COMO_DO_TIPO.fetch(tipo).exclude?(como)

    linha.merge(values: valores(chave, como, linha[:values], sim_nao: sim_nao?(chave, tipo)))
  end

  def conferir_ligacao(chave, ligacao, ultima)
    return if ultima && ligacao.blank?
    return if !ultima && ligacao.is_a?(String) && LIGACOES.include?(ligacao.downcase)

    recusar("#{chave}: ligação inválida")
  end

  def valores(chave, como, recebidos, sim_nao:)
    recusar("#{chave}: valores em formato inválido") unless recebidos.nil? || recebidos.is_a?(Array)
    lista = Array(recebidos)
    return [] if SEM_VALOR.include?(como)

    recusar("#{chave}: valor que falta") if lista.empty?
    recusar("#{chave}: valores demais") if lista.size > MAXIMO_DE_VALORES
    return sim_ou_nao(chave, lista) if sim_nao

    recusar("#{chave}: valor em formato inválido") unless lista.all? { |valor| valor.is_a?(String) && valor.strip.present? }
    lista
  end

  def sim_ou_nao(chave, lista)
    recusar("#{chave}: valor em formato inválido") unless lista.one? && [true, false].include?(lista.first)
    lista
  end

  def sim_nao?(chave, tipo)
    tipo == 'boolean' || padroes.dig(chave, 'data_type') == 'boolean'
  end

  # O tipo do campo da conta com essa chave, ou nil (campo padrão, ou que não existe: o filtro recusa).
  def tipo_da_conta(chave)
    return if padroes.key?(chave)

    tipo = campos_da_conta[chave]
    return if tipo.nil?

    FilterService::ATTRIBUTE_TYPES[tipo] || recusar("#{chave}: campo que a lista não filtra")
  end

  def padroes
    @padroes ||= YAML.safe_load_file('./lib/filters/filter_keys.yml').fetch('contacts')
  end

  def campos_da_conta
    @campos_da_conta ||= @account.custom_attribute_definitions.where(attribute_model: 'contact_attribute')
                                 .pluck(:attribute_key, :attribute_display_type).to_h
  end

  def recusar(motivo)
    raise Relacionamentos::PedidoInvalido, "condicoes: #{motivo}"
  end
end
