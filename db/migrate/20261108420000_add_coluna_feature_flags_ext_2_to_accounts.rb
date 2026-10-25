# #2186: a feature_flags_ext_1 não tem mais vaga. As posições 1 a 61 estão em uso (a 61 é a meta_ads_gestao, #2164) e
# a 62 e a 63 estão provisórias para o #2182 e o #2183 (Orquestração, 25/10). Terceira coluna de flags da conta, no
# molde da ext_1; default 0: nenhuma conta existente muda. O nome da classe não pode ser AddFeatureFlagsExt2ToAccounts,
# que já existe em 20260706215758 (aquela, apesar do nome, cria a ext_1).
# accounts é tabela quente e o ADD COLUMN pede ACCESS EXCLUSIVE: o lock_timeout de 5 s com 3 tentativas do
# StrongMigrations (config/initializers/strong_migrations.rb) faz a migration desistir rápido em vez de travar a conta.
class AddColunaFeatureFlagsExt2ToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :feature_flags_ext_2, :bigint, default: 0, null: false
  end
end
