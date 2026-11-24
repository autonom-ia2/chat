# Um movimento do cartão fidelidade de uma pessoa (#3100): o histórico, só acrescentado. `quantos` tem sinal: a entrada
# (compra, presente, ajuste para mais) é positiva; a saída (prêmio, vencimento, estorno, ajuste para menos), negativa.
#
# A entrada guarda quanto dela ainda não saiu (`restante`) e quando vence (`vence_em`, pela validade do cartão). As
# saídas tiram das entradas mais antigas primeiro, e o vencimento leva o que sobrou de cada uma (Fidelidade::Carteira).
# A soma dos `restante` de uma pessoa é o saldo dela.
#
# A compra e o estorno apontam para o card (`origem`). O índice único (cartão, pessoa, card, tipo, vez) impede o mesmo
# card de dar carimbo duas vezes; o card desfeito e ganho de novo é a vez seguinte (Fidelidade::DarPelaCompra).
#
# Só é gravado por Fidelidade::Carteira, junto do saldo.
class Fidelidade::Movimento < ApplicationRecord
  self.table_name = 'fidelidade_movimentos'

  COMPRA = 'compra'.freeze
  PRESENTE = 'presente'.freeze
  AJUSTE = 'ajuste'.freeze
  PREMIO = 'premio'.freeze
  VENCEU = 'venceu'.freeze
  ESTORNO = 'estorno'.freeze
  TIPOS = [COMPRA, PRESENTE, AJUSTE, PREMIO, VENCEU, ESTORNO].freeze
  DO_CARD = [COMPRA, ESTORNO].freeze
  MOTIVO_MAXIMO = 60
  CENTAVOS = 100.0

  belongs_to :account
  belongs_to :contact
  belongs_to :programa, class_name: 'Fidelidade::Programa', inverse_of: :movimentos
  belongs_to :user, optional: true
  belongs_to :origem, polymorphic: true, optional: true

  validates :tipo, inclusion: { in: TIPOS }
  validates :quantos, numericality: { only_integer: true }
  # O estorno de quem já usou os carimbos sai com zero: fecha a compra sem deixar o saldo negativo.
  validates :quantos, numericality: { other_than: 0 }, unless: -> { tipo == ESTORNO }
  validates :restante, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :vez, numericality: { only_integer: true, greater_than: 0 }
  validates :motivo, length: { maximum: MOTIVO_MAXIMO }

  scope :da_pessoa, ->(programa, contact_id) { where(programa_id: programa.id, contact_id: contact_id) }
  scope :com_resto, -> { where('restante > 0') }
  scope :a_vencer, ->(agora) { com_resto.where.not(vence_em: nil).where(vence_em: ...agora) }
  scope :mais_novos_antes, -> { order(created_at: :desc, id: :desc) }

  # Como a ficha lê (historico.js): a data em segundos, quem fez e, para quem vê valor de venda, o valor da compra.
  def para_a_tela(com_valores:)
    { id: id, tipo: tipo, quantos: quantos, em: created_at.to_i, quem: user&.name, motivo: motivo,
      valor: (com_valores && valor_centavos ? { total: valor_centavos / CENTAVOS, moeda: moeda } : nil) }
  end
end
