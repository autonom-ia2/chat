# #2186: a feature_flags_ext_1 não tem mais vaga. As posições 1 a 61 estão em uso (a 61 é a meta_ads_gestao, #2164) e
# a 62 e a 63 estão provisórias para o #2182 e o #2183 (Orquestração, 25/10). Terceira coluna de flags da conta, no
# molde da ext_1; default 0: nenhuma conta existente muda. O nome da classe não pode ser AddFeatureFlagsExt2ToAccounts,
# que já existe em 20260706215758 (aquela, apesar do nome, cria a ext_1).
# accounts é tabela quente: o ADD COLUMN pede ACCESS EXCLUSIVE e, atrás de uma transação longa, ficaria na fila travando
# toda leitura da conta. Com lock_timeout de 5 s a migration falha rápido e o deploy aborta limpo (rodar de novo
# depois). SET LOCAL: vale só na transação desta migration. O StrongMigrations (start_after 20261108260000) já põe
# lock_timeout de 5 s com 3 tentativas; o SET LOCAL deixa o limite explícito aqui, e o safety_assured é porque ele não
# analisa um execute.
class AddColunaFeatureFlagsExt2ToAccounts < ActiveRecord::Migration[7.2]
  def up
    safety_assured { execute "SET LOCAL lock_timeout = '5s'" }
    add_column :accounts, :feature_flags_ext_2, :bigint, default: 0, null: false
  end

  def down
    safety_assured { execute "SET LOCAL lock_timeout = '5s'" }
    remove_column :accounts, :feature_flags_ext_2
  end
end
