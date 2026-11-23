# Um cupom da conta (#3100): o que ele dá (desconto em %, em dinheiro ou um presente), o começo do código e quanto tempo
# vale depois de chegar à pessoa. Cada pessoa recebe um código só dela (Fidelidade::CupomCodigo). O nome só a conta vê.
#
# A oferta: em `porcentagem`, `oferta_valor` é a % (1 a 100); em `valor`, centavos na `moeda`; em `presente`, o texto.
# O prefixo é só letra maiúscula e número, até 8, conferido letra a letra (regras.js#prefixoLimpo faz o mesmo na tela).
class Fidelidade::Cupom < ApplicationRecord
  self.table_name = 'fidelidade_cupons'

  PORCENTAGEM = 'porcentagem'.freeze
  VALOR = 'valor'.freeze
  PRESENTE = 'presente'.freeze
  OFERTAS = [PORCENTAGEM, VALOR, PRESENTE].freeze
  VALIDADES = [7, 15, 30, 60].freeze
  PREFIXO_MAXIMO = 8
  NOME_MAXIMO = 60
  TEXTO_MAXIMO = 60
  PORCENTAGEM_MAXIMA = 100
  LETRAS_DO_PREFIXO = [*'A'..'Z', *'0'..'9'].freeze
  CENTAVOS = 100.0

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :codigos, class_name: 'Fidelidade::CupomCodigo', inverse_of: :cupom, dependent: nil

  validates :nome, presence: true, length: { maximum: NOME_MAXIMO }
  validates :oferta_tipo, inclusion: { in: OFERTAS }
  validates :oferta_valor, numericality: { only_integer: true, greater_than: 0 }, if: -> { oferta_tipo != PRESENTE }
  validates :oferta_valor, numericality: { less_than_or_equal_to: PORCENTAGEM_MAXIMA }, if: -> { oferta_tipo == PORCENTAGEM }
  validates :oferta_texto, presence: true, if: -> { oferta_tipo == PRESENTE }
  validates :oferta_texto, length: { maximum: TEXTO_MAXIMO }
  validates :moeda, presence: true, if: -> { oferta_tipo == VALOR }
  validates :prefixo, presence: true, length: { maximum: PREFIXO_MAXIMO }
  validates :validade_dias, inclusion: { in: VALIDADES }
  validates :limite_por_cliente, numericality: { only_integer: true, greater_than: 0 }
  validate :prefixo_so_letras_e_numeros

  scope :da_conta, ->(account) { where(account_id: account.id) }

  # A oferta como a tela lê (useTextosDaFidelidade#oferta): o valor em dinheiro vai em reais.
  def oferta
    valor = oferta_tipo == VALOR ? oferta_valor.to_i / CENTAVOS : oferta_valor
    { tipo: oferta_tipo, valor: valor, texto: oferta_texto }
  end

  # Como a tela lê (LinhaDoCupom, MontarCupom, o passo "Mandar cupom"), sem os números do relatório.
  def para_a_tela
    { id: id, nome: nome, oferta: oferta, moeda: moeda, prefixo: prefixo, validade_dias: validade_dias,
      limite_por_cliente: limite_por_cliente, ligado: ligado }
  end

  private

  def prefixo_so_letras_e_numeros
    return if prefixo.blank? || prefixo.each_char.all? { |letra| LETRAS_DO_PREFIXO.include?(letra) }

    errors.add(:prefixo, :invalid)
  end
end
