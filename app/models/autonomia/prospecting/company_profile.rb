# Empresa pesquisada na Prospecção (#679): cadastro público de um CNPJ, compartilhado entre contas e reaproveitado por
# REUSE_WINDOW. Da pessoa física guarda só a lista fechada de Research::PersonFields; menor de idade não entra.
class Autonomia::Prospecting::CompanyProfile < ApplicationRecord
  self.table_name = 'autonomia_prospecting_company_profiles'

  REUSE_WINDOW = 90.days

  validates :cnpj, presence: true, uniqueness: true, length: { is: 14 }
  validates :verified_at, presence: true

  def verified_since?(time)
    verified_at.present? && verified_at >= time
  end

  # A escolha do dono guardada vale só para o mesmo tipo de decisor pedido.
  def owner_selection_for?(requested_role)
    data.to_h['requested_role'] == requested_role
  end
end
