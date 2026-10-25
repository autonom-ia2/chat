# #2186: a feature_flags_ext_1 lotou (63 posições). Terceira coluna de flags da conta, no molde da ext_1.
# Default 0: nenhuma conta existente muda. O nome da classe não pode ser AddFeatureFlagsExt2ToAccounts,
# que já existe em 20260706215758 (aquela, apesar do nome, cria a ext_1).
class AddColunaFeatureFlagsExt2ToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :feature_flags_ext_2, :bigint, default: 0, null: false
  end
end
