# O que a cotação da renovação pede do segurado e a apólice traz escrito (E8.1, #3043), na apólice da carteira:
# nascimento, sexo, CEP, placa e classe de bônus. Todos podem faltar (nulo é "não sei").
#
# - `segurado_nascimento`: AAAA-MM-DD, uma data que existe e não está no futuro. É dado pessoal: vai cifrado (não
#   determinístico) quando a instalação tem as chaves, como as outras colunas cifradas do fork. Sem as chaves fica em
#   texto puro e tudo funciona igual;
# - `segurado_sexo`: F ou M;
# - `cep`: 8 dígitos, sem traço;
# - `placa`: 7 letras ou dígitos, as 3 primeiras letras, em maiúsculas, sem traço nem espaço (a forma do portal, que
#   vale para a placa antiga e para a do Mercosul);
# - `bonus_classe`: de 0 a 10.
# O banco confere sexo, CEP e bônus (CHECK); o nascimento só aqui, porque o banco vê o texto cifrado. Tudo sem expressão
# regular: a forma é conferida tirando os caracteres que podem estar e vendo se sobrou algum.
#
# Os cinco nunca aparecem em `inspect`, em log de parâmetro filtrado nem no JSON padrão do model. As mensagens de
# validação não repetem o valor.
module Carteira::DadosDoSegurado
  extend ActiveSupport::Concern

  COLUNAS = %i[segurado_nascimento segurado_sexo cep placa bonus_classe].freeze
  SEXOS = %w[F M].freeze
  DIGITOS_DO_CEP = 8
  TAMANHO_DA_PLACA = 7
  BONUS = (0..10)
  DIGITOS = '0-9'.freeze
  DA_PLACA = 'A-Z0-9'.freeze
  LETRAS = 'A-Z'.freeze
  LETRAS_DA_PLACA = 3

  included do
    # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
    encrypts :segurado_nascimento if Chatwoot.encryption_configured?
    self.filter_attributes += COLUNAS

    validates :segurado_sexo, inclusion: { in: SEXOS }, allow_nil: true
    validates :bonus_classe, numericality: { only_integer: true, in: BONUS }, allow_nil: true
    validate :forma_dos_dados_do_segurado
  end

  # O JSON padrão do model sai sem os dados do segurado: quem mostra o seguro é Carteira::Apresentacao.
  def serializable_hash(options = nil)
    opcoes = options.to_h
    super(opcoes.merge(except: Array(opcoes[:except]) + COLUNAS))
  end

  # A data AAAA-MM-DD que existe, escrita de volta igual, e não é de amanhã em diante.
  def self.nascimento?(texto)
    data = Date.iso8601(texto.to_s)
    data.iso8601 == texto && data <= Date.current
  rescue Date::Error
    false
  end

  def self.cep?(texto)
    texto.is_a?(String) && texto.size == DIGITOS_DO_CEP && texto.delete(DIGITOS).empty?
  end

  def self.placa?(texto)
    texto.is_a?(String) && texto.size == TAMANHO_DA_PLACA && texto.delete(DA_PLACA).empty? &&
      texto.first(LETRAS_DA_PLACA).delete(LETRAS).empty?
  end

  private

  def forma_dos_dados_do_segurado
    errors.add(:segurado_nascimento, :invalid) unless segurado_nascimento.nil? || Carteira::DadosDoSegurado.nascimento?(segurado_nascimento)
    errors.add(:cep, :invalid) unless cep.nil? || Carteira::DadosDoSegurado.cep?(cep)
    errors.add(:placa, :invalid) unless placa.nil? || Carteira::DadosDoSegurado.placa?(placa)
  end
end
