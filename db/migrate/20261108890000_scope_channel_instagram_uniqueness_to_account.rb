# #2781: o mesmo Instagram ligado em mais de uma conta, como a Página do Facebook (índice único em page_id e
# account_id). Troca o índice único global de instagram_id por um único em (instagram_id, account_id).
#
# Sem travar as escritas: os índices entram e saem com concurrently, fora de transação. A ordem protege a unicidade o
# tempo todo: primeiro nasce o índice novo (o global garante que não há duplicata), e só então cai o global. O índice
# novo começa por instagram_id, então continua servindo as buscas do webhook por instagram_id. Cada passo pode rodar de
# novo sem erro se o deploy cair no meio.
#
# Rollback: `rails db:migrate:down VERSION=20261108890000`. Ele recria o único global e falha, sem apagar nada, se o
# mesmo Instagram já estiver ligado em duas contas; aí é preciso desligar uma das caixas antes.
class ScopeChannelInstagramUniquenessToAccount < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  GLOBAL = 'index_channel_instagram_on_instagram_id'.freeze
  BY_ACCOUNT = 'index_channel_instagram_on_instagram_id_and_account_id'.freeze

  def up
    add_index :channel_instagram, [:instagram_id, :account_id],
              unique: true, name: BY_ACCOUNT, algorithm: :concurrently, if_not_exists: true
    remove_index :channel_instagram, name: GLOBAL, algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :channel_instagram, :instagram_id, unique: true, name: GLOBAL, algorithm: :concurrently, if_not_exists: true
    remove_index :channel_instagram, name: BY_ACCOUNT, algorithm: :concurrently, if_exists: true
  end
end
