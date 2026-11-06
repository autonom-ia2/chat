# Quem salvou o Decisor por último (#2558, parecer da Funções personalizadas): o Decisor só lê o anúncio de origem do
# card quando essa pessoa tem `meta_ads_view` (Crm::AnuncioDeOrigem.ve?). Decisor antigo fica sem ninguém e não lê o
# anúncio até ser salvo de novo.
#
# Sem chave estrangeira: a leitura procura a pessoa entre os membros da conta (Autonomia::Decisor#ve_o_anuncio?), então
# quem saiu da conta ou foi apagado já não abre o anúncio. O índice entra sem travar a tabela. A trava curta do
# add_column fica com o lock_timeout de 5 s (3 tentativas) do config/initializers/strong_migrations.rb, que vale para
# toda migration; um índice concorrente que falhar e ficar inválido é apagado antes da nova tentativa
# (remove_invalid_indexes).
class AddSalvoPorToAutonomiaDecisores < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_reference :autonomia_decisores, :salvo_por, index: { algorithm: :concurrently }
  end
end
