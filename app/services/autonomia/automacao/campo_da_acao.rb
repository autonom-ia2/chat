# O campo de destino de cada valor calculado no corpo de uma ação (G16 do #2414), pelo formato da ação no Guia
# (formatos-das-acoes.json). Só o campo do primeiro nível (dentro do envelope) tem tipo conhecido; dentro de um campo
# JSON (custom_attributes) qualquer valor cabe, como na tela. Campo sem tipo no formato também aceita qualquer valor.
#
# - No salvar: o exemplo que a Conferência do formato vê no lugar do valor calculado, e a forma que o campo nunca
#   aceitaria (texto montado ou data num campo de opções, de número, de sim/não).
# - Ao executar: o valor de verdade cabe no tipo do campo? Não cabendo, a ação pula (valor_fora_do_formato), nunca
#   grava.
class Autonomia::Automacao::CampoDaAcao
  # O que cada forma produz; o `$valor` só se sabe ao executar.
  PRODUZ = { '$texto' => 'texto', '$data' => 'data' }.freeze
  # Os tipos que aceitam o que cada forma produz. Tipo conhecido fora daqui não aceita nenhum dos dois.
  ACEITA = { 'string' => %w[texto data], 'data_hora' => %w[data] }.freeze
  EXEMPLOS = { 'inteiro' => 1, 'id' => 1, 'numero' => 1, 'booleano' => true, 'lista' => [], 'lista_de_objetos' => [],
               'objeto' => {}, 'objeto_livre' => {}, 'json' => {} }.freeze
  CABE = {
    'string' => ->(valor) { valor.is_a?(String) || valor.is_a?(Numeric) },
    'inteiro' => ->(valor) { valor.is_a?(Integer) },
    'id' => ->(valor) { valor.is_a?(Integer) },
    'numero' => ->(valor) { valor.is_a?(Numeric) },
    'booleano' => ->(valor) { [true, false].include?(valor) },
    'data_hora' => ->(valor) { Autonomia::Automacao::CampoDaAcao.data?(valor) },
    'lista' => ->(valor) { valor.is_a?(Array) },
    'lista_de_objetos' => ->(valor) { valor.is_a?(Array) },
    'objeto' => ->(valor) { valor.is_a?(Hash) },
    'objeto_livre' => ->(valor) { valor.is_a?(Hash) },
    'json' => ->(valor) { valor.is_a?(Hash) },
    'arquivo' => ->(_valor) { false }
  }.freeze

  # O que impede a ação com o corpo já montado: o formato da ação (opção fora da lista) e o tipo de cada campo que
  # recebeu valor calculado. Vazio = segue. O motor e o ensaio perguntam aqui.
  def self.problemas(acao, original, montado, conta:)
    campos = new(acao)
    tipos = ::Autonomia::Automacao::Corpo.lugares(original).reject { |onde, _folha| campos.cabe?(onde, montado.dig(*onde)) }
    ::Autonomia::Guide::Formatos::Conferencia.new(acao, montado, conta: conta).problemas_em_texto +
      tipos.map { |onde, _folha| "#{campos.nome(onde)}: o valor calculado não é do tipo deste campo" }
  end

  # "AAAA-MM-DD", com ou sem a hora depois: como a tela grava e lê uma data.
  def self.data?(valor)
    valor.is_a?(String) && Date.iso8601(valor.split('T').first.split.first.to_s).present?
  rescue Date::Error
    false
  end

  def initialize(acao)
    @formato = ::Autonomia::Guide::Formatos.para(acao.to_s) || {}
  end

  def nome(onde) = partes(onde).first.to_s

  # O campo do formato no lugar `onde` do corpo; nil dentro de um campo JSON, fora do formato ou sem tipo.
  def campo(onde)
    lista = partes(onde)
    info = lista.one? ? @formato.dig('campos', lista.first) : nil
    info if info.is_a?(Hash)
  end

  # A forma que o campo nunca aceitaria: texto montado ou data num campo de opções ou de outro tipo.
  def recusa?(onde, folha)
    forma = PRODUZ.keys.find { |chave| folha.key?(chave) }
    info = campo(onde)
    return false unless forma && info
    return true if info['um_de'].present?

    info['tipo'].present? && Array(ACEITA[info['tipo']]).exclude?(PRODUZ[forma])
  end

  # O exemplo que a Conferência vê no salvar: a primeira opção de um campo com lista; senão, um valor do tipo dele.
  def exemplo(onde, folha)
    info = campo(onde)
    return info['um_de'].first if info && info['um_de'].present?
    return Date.current.iso8601 if folha.key?('$data') || info&.dig('tipo') == 'data_hora'

    EXEMPLOS.fetch(info&.dig('tipo'), 'texto')
  end

  def cabe?(onde, valor)
    info = campo(onde)
    info.nil? || CABE.fetch(info['tipo'], ->(_valor) { true }).call(valor)
  end

  private

  def partes(onde) = onde.first == @formato['envelope'] ? onde.drop(1) : onde
end
