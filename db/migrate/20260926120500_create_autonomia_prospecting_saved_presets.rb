# JOGADAS SALVAS DA PROSPECÇÃO (chat#732, E8 item 2; MODO-25, MODO-26, FILTRO-27, PLAT-17).
#
# Tabela própria em vez do metadata de autonomia_prospecting_settings: aquele jsonb é regravado inteiro pelas
# configurações da conta e pelo console do superadmin (score_engine), e uma jogada salva no meio seria apagada em
# silêncio. Uma linha por jogada também dá id estável para a busca guardar e índice para o nome não repetir na conta.
# Tabela nova e vazia: nada existente muda. Apagar a conta apaga as jogadas; apagar o usuário só esquece quem salvou.
class CreateAutonomiaProspectingSavedPresets < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_prospecting_saved_presets do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: true, index: { name: 'idx_autonomia_prospecting_saved_presets_user' },
                          foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.string :score_mode, null: false
      t.jsonb :filters, null: false, default: {}
      t.timestamps
    end

    add_index :autonomia_prospecting_saved_presets, 'account_id, lower(name)',
              unique: true, name: 'idx_autonomia_prospecting_saved_presets_account_name'
  end
end
