# #2406: a caixa do Instagram também pode nascer do login único (Facebook Login for Business), com o token da Página.
# `login` diz de qual login veio a caixa ('instagram', o de sempre, ou 'facebook'); `page_id` é a Página dona do token,
# por onde o Direct sai (/{page_id}/messages) e a Página que se inscreve no webhook.
#
# Só colunas novas. O default 'instagram' vale para toda caixa que já existe, e o Postgres o grava sem reescrever a
# tabela. Rollback: `rails db:migrate:down VERSION=20261108900000`. Antes, as caixas com login 'facebook' voltam ao
# login do Instagram (docs/crm/instagram-login-unico-2406.md).
class AddLoginToChannelInstagram < ActiveRecord::Migration[7.2]
  def change
    add_column :channel_instagram, :login, :string, default: 'instagram', null: false, if_not_exists: true
    add_column :channel_instagram, :page_id, :string, if_not_exists: true
  end
end
