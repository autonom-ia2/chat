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
  # A capital de cada estado: desempata a cidade sem UF com o mesmo nome em mais de um estado, quando uma delas é a
  # capital (Rio Branco é a do Acre, não a de Mato Grosso; varredura F39).
  CAPITAIS = {
    'AC' => 'Rio Branco', 'AL' => 'Maceió', 'AP' => 'Macapá', 'AM' => 'Manaus', 'BA' => 'Salvador', 'CE' => 'Fortaleza',
    'DF' => 'Brasília', 'ES' => 'Vitória', 'GO' => 'Goiânia', 'MA' => 'São Luís', 'MT' => 'Cuiabá', 'MS' => 'Campo Grande',
    'MG' => 'Belo Horizonte', 'PA' => 'Belém', 'PB' => 'João Pessoa', 'PR' => 'Curitiba', 'PE' => 'Recife',
    'PI' => 'Teresina', 'RJ' => 'Rio de Janeiro', 'RN' => 'Natal', 'RS' => 'Porto Alegre', 'RO' => 'Porto Velho',
    'RR' => 'Boa Vista', 'SC' => 'Florianópolis', 'SP' => 'São Paulo', 'SE' => 'Aracaju', 'TO' => 'Palmas'
  }.freeze

  module_function

  def nome(sigla)
    NOMES[sigla.to_s.upcase]
  end

  # O nome do estado como a fonte escreveu ("São Paulo", "SAO PAULO") -> "SP"; nil quando não é um estado do Brasil.
  # Comparação exata do nome sem acento e sem caixa: não é interpretação de texto de pessoa, é o nome oficial.
  def sigla_pelo_nome(nome)
    alvo = Autonomia::FerramentasProntas::Lista.comparavel(nome)
    NOMES.find { |_sigla, oficial| Autonomia::FerramentasProntas::Lista.comparavel(oficial) == alvo }&.first
  end

  def capital?(sigla, nome)
    Autonomia::FerramentasProntas::Lista.comparavel(CAPITAIS[sigla.to_s.upcase]) == Autonomia::FerramentasProntas::Lista.comparavel(nome)
  end

  # "AC" -> { 'uf' => 'AC', 'estado' => 'Acre' }
  def com_nome(sigla)
    { 'uf' => sigla, 'estado' => nome(sigla) }
  end
end
