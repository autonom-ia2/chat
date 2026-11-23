# O código de um cupom para uma pessoa (#3100): "VOLTA-7KD2". Um por pessoa e cupom (mandar de novo reaproveita o
# código) e único na conta. Vale até `vale_ate` (contado de quando chegou); marcado como usado, guarda quando e quem.
class Fidelidade::CupomCodigo < ApplicationRecord
  self.table_name = 'fidelidade_cupom_codigos'

  VALIDO = 'valido'.freeze
  USADO = 'usado'.freeze
  VENCIDO = 'vencido'.freeze
  CODIGO_MAXIMO = 20

  belongs_to :account
  belongs_to :cupom, class_name: 'Fidelidade::Cupom', inverse_of: :codigos
  belongs_to :contact
  belongs_to :usado_por, class_name: 'User', optional: true

  validates :codigo, presence: true, length: { maximum: CODIGO_MAXIMO }, uniqueness: { scope: :account_id }
  validates :contact_id, uniqueness: { scope: :cupom_id }
  validates :usos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def estado(agora)
    return USADO if usado_em
    return VENCIDO if vale_ate && vale_ate < agora

    VALIDO
  end

  # Como a ficha lê (SecaoFidelidade): o código, o estado, a oferta e as datas em segundos.
  def para_a_ficha(agora)
    { id: id, codigo: codigo, estado: estado(agora), oferta: cupom.oferta, moeda: cupom.moeda, vale_ate: vale_ate&.to_i,
      usado_em: usado_em&.to_i }
  end
end
