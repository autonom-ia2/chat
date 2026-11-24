# O saldo pronto de uma pessoa no cartão fidelidade da conta (#3100), para a ficha, o painel e o filtro "perto do
# prêmio" da Lista de Relacionamentos. Muda só na mesma transação do movimento, com a linha travada
# (Fidelidade::Carteira): dois "Dar o prêmio" ao mesmo tempo passam um de cada vez.
class Fidelidade::Saldo < ApplicationRecord
  self.table_name = 'fidelidade_saldos'

  belongs_to :account
  belongs_to :contact
  belongs_to :programa, class_name: 'Fidelidade::Programa', inverse_of: :saldos

  validates :saldo, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :contact_id, uniqueness: { scope: :programa_id }
end
