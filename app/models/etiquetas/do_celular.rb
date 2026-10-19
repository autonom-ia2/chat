# Etiqueta do WhatsApp do celular (#1823, F1b): liga a etiqueta do app WhatsApp Business de uma caixa (`label_wa_id`) à
# etiqueta daqui (`Label`), com o nome e o índice de cor que ela tem no celular. Uma por etiqueta do celular em cada caixa
# (índice único inbox_id + label_wa_id). `evento_em` guarda o `at` do último evento aplicado; `apagada_em`, quando ela foi
# apagada no celular (a linha fica como marca, para um evento atrasado não a trazer de volta). Quem grava é o
# Etiquetas::AplicarEventoDoCelular; o `Label` do Chatwoot não ganha associação nem coluna, e apagar a caixa, a etiqueta
# ou a conta apaga a correspondência pela chave estrangeira.
class Etiquetas::DoCelular < ApplicationRecord
  self.table_name = 'etiquetas_do_celular'

  belongs_to :account
  belongs_to :inbox
  belongs_to :label, optional: true

  scope :vivas, -> { where(apagada_em: nil) }

  validates :label_wa_id, :evento_em, presence: true
  validates :label, presence: true, unless: :apagada?
  validate :tudo_da_mesma_conta

  def apagada?
    apagada_em.present?
  end

  private

  def tudo_da_mesma_conta
    errors.add(:inbox, :invalid) if inbox.present? && inbox.account_id != account_id
    errors.add(:label, :invalid) if label.present? && label.account_id != account_id
  end
end
