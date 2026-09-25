# PERFIL DE NOTA RESTRITO A CONTAS (chat#681, E5 frente C).
#
# Perfil sem linha aqui é global, como todos os perfis eram antes; com linhas, só aparece e só vale para as contas
# listadas. Tabela nova e vazia: nenhum perfil existente muda de alcance. Apagar o perfil ou a conta apaga o vínculo.
class CreateAutonomiaProspectingScoringProfileAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_prospecting_scoring_profile_accounts do |t|
      t.references :scoring_profile, null: false, index: false,
                                     foreign_key: { to_table: :autonomia_prospecting_scoring_profiles, on_delete: :cascade }
      t.references :account, null: false, index: { name: 'idx_autonomia_prospecting_scoring_profile_accounts_account' },
                             foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :autonomia_prospecting_scoring_profile_accounts, [:scoring_profile_id, :account_id],
              unique: true, name: 'idx_autonomia_prospecting_scoring_profile_accounts_unique'
  end
end
