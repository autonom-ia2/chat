# #3119 (upgrade Chatwoot 4.19.1): as 8 flags novas do upstream foram para a feature_flags_ext_2 (posições 51 a 58),
# porque no upstream elas ocupam posições da ext_1 que o fork já usa. A ext_2 fica com 58 de 63; esta é a reserva para
# as próximas. Mesmo molde da ext_2 (#2186): default 0, nenhuma conta existente muda. O ADD COLUMN em accounts pede
# ACCESS EXCLUSIVE; o lock_timeout do StrongMigrations faz a migration desistir rápido em vez de travar a tabela.
class AddColunaFeatureFlagsExt3ToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :feature_flags_ext_3, :bigint, default: 0, null: false
  end
end
