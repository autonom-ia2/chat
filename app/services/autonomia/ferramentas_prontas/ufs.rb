# OS ESTADOS DO BRASIL (#2858, F1), usados por várias fontes: a sigla como parâmetro (Cidades), o nome que a fonte de
# geolocalização devolve virando sigla (Localização), a região fiscal do CPF e o DDD de reserva.
module Autonomia::FerramentasProntas::Ufs
  NOMES = {
    'AC' => 'Acre', 'AL' => 'Alagoas', 'AP' => 'Amapá', 'AM' => 'Amazonas', 'BA' => 'Bahia', 'CE' => 'Ceará',
    'DF' => 'Distrito Federal', 'ES' => 'Espírito Santo', 'GO' => 'Goiás', 'MA' => 'Maranhão', 'MT' => 'Mato Grosso',
    'MS' => 'Mato Grosso do Sul', 'MG' => 'Minas Gerais', 'PA' => 'Pará', 'PB' => 'Paraíba', 'PR' => 'Paraná',
    'PE' => 'Pernambuco', 'PI' => 'Piauí', 'RJ' => 'Rio de Janeiro', 'RN' => 'Rio Grande do Norte',
    'RS' => 'Rio Grande do Sul', 'RO' => 'Rondônia', 'RR' => 'Roraima', 'SC' => 'Santa Catarina', 'SP' => 'São Paulo',
    'SE' => 'Sergipe', 'TO' => 'Tocantins'
  }.freeze
  SIGLAS = NOMES.keys.freeze

  module_function

  def nome(sigla)
    NOMES[sigla.to_s.upcase]
  end

  # O nome do estado como a fonte escreveu ("São Paulo", "SAO PAULO") -> "SP"; nil quando não é um estado do Brasil.
  # Comparação exata do nome sem acento e sem caixa: não é interpretação de texto de pessoa, é o nome oficial.
  def sigla_pelo_nome(nome)
    alvo = comparavel(nome)
    NOMES.find { |_sigla, oficial| comparavel(oficial) == alvo }&.first
  end

  def comparavel(texto)
    I18n.transliterate(texto.to_s).downcase.squish
  end

  # "AC" -> { 'uf' => 'AC', 'estado' => 'Acre' }
  def com_nome(sigla)
    { 'uf' => sigla, 'estado' => nome(sigla) }
  end
end
