# O código de um cupom para uma pessoa (#3100): "VOLTA-7KD2". Um por pessoa e cupom (mandar de novo reaproveita o
# código) e único na conta. Vale até `vale_ate` (contado de quando chegou); marcado como usado, guarda quando e quem.
#
# A forma limpa (`codigo_limpo`, "VOLTA7KD2") é a que o Conferir procura e a que é única na conta: quem está no balcão
# digita com ou sem o hífen, com espaço ou em minúsculas, e acha o mesmo código. Sai de `codigo`, sempre.
class Fidelidade::CupomCodigo < ApplicationRecord
  self.table_name = 'fidelidade_cupom_codigos'

  VALIDO = 'valido'.freeze
  USADO = 'usado'.freeze
  VENCIDO = 'vencido'.freeze
  CODIGO_MAXIMO = 20
  # O que não conta na comparação: o separador do código (Fidelidade::CodigoDoCupom::SEPARADOR).
  SEPARADOR = '-'.freeze

  belongs_to :account
  belongs_to :cupom, class_name: 'Fidelidade::Cupom', inverse_of: :codigos
  belongs_to :contact
  belongs_to :usado_por, class_name: 'User', optional: true

  before_validation { self.codigo_limpo = self.class.limpo(codigo) }

  validates :codigo, presence: true, length: { maximum: CODIGO_MAXIMO }
  validates :codigo_limpo, presence: true, uniqueness: { scope: :account_id }
  validates :contact_id, uniqueness: { scope: :cupom_id }
  validates :usos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Maiúsculas, sem espaço e sem o hífen, letra a letra (sem expressão regular), como regras.js#codigoDigitado.
  def self.limpo(texto)
    texto.to_s.upcase.each_char.reject { |letra| letra.strip.empty? || letra == SEPARADOR }.join
  end

  def estado(agora)
    return USADO if usado_em
    return VENCIDO if vale_ate && vale_ate < agora

    VALIDO
  end

  # Como a ficha lê (SecaoFidelidade): o código, o estado, a oferta e as datas em segundos. O código vivo só vai
  # `com_codigo` (quem pode usá-lo ou vê o painel Fidelidade); sem ele, a ficha mostra o estado e a oferta.
  def para_a_ficha(agora, com_codigo:)
    ficha = { id: id, codigo: codigo, estado: estado(agora), oferta: cupom.oferta, moeda: cupom.moeda, vale_ate: vale_ate&.to_i,
              usado_em: usado_em&.to_i }
    com_codigo ? ficha : ficha.except(:codigo)
  end
end
