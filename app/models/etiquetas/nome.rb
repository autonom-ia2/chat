# Nome livre da etiqueta (#1823, F1a): o que o atendente digitou ("Novo Cliente"), um por etiqueta. Só exibição: o
# `Label#title` segue como chave técnica. Quem grava é o Api::V1::Accounts::NomesDeEtiquetasController; apagar a
# etiqueta apaga o nome pela chave estrangeira (on_delete: cascade), sem associação nova no Label do Chatwoot.
class Etiquetas::Nome < ApplicationRecord
  self.table_name = 'etiquetas_nomes'

  TAMANHO_MAXIMO = 80

  belongs_to :account
  belongs_to :label

  validates :nome, presence: true, length: { maximum: TAMANHO_MAXIMO }
  validates :label_id, uniqueness: true
  validate :etiqueta_da_mesma_conta

  private

  def etiqueta_da_mesma_conta
    return if label.blank? || label.account_id == account_id

    errors.add(:label, :invalid)
  end
end
