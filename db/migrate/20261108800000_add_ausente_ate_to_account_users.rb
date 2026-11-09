# #2414 G23 (#2737, decisão do Rodrigo, opção 1): até quando a pessoa está ausente na conta (férias, licença). Marcado
# na Equipe (admin e quem tem people_manage) ou pela própria pessoa no perfil; a Automação livre lê numa condição.
# Coluna nula, sem default: vazio é "não está ausente". Aditiva.
class AddAusenteAteToAccountUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :account_users, :ausente_ate, :datetime
  end
end
