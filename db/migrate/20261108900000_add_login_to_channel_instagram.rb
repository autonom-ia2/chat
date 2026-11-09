# #2406: a caixa do Instagram também pode nascer do login único (Facebook Login for Business), com o token da Página.
# `login` diz de qual login veio a caixa ('instagram', o de sempre, ou 'facebook'); `page_id` é a Página dona do token,
# por onde o Direct sai (/{page_id}/messages) e a Página que se inscreve no webhook.
#
# Só colunas novas. O default 'instagram' vale para toda caixa que já existe, e o Postgres o grava sem reescrever a
# tabela. Rollback: `rails db:migrate:down VERSION=20261108900000`. Ele para, sem apagar nada, se ainda houver caixa
# com login 'facebook': ela ficaria com o token da Página falando com graph.instagram.com. Antes, essas caixas voltam
# ao login do Instagram (docs/crm/instagram-login-unico-2406.md).
class AddLoginToChannelInstagram < ActiveRecord::Migration[7.2]
  def up
    add_column :channel_instagram, :login, :string, default: 'instagram', null: false, if_not_exists: true
    add_column :channel_instagram, :page_id, :string, if_not_exists: true
  end

  def down
    facebook = select_value("SELECT 1 FROM channel_instagram WHERE login = 'facebook' LIMIT 1")
    raise 'há caixa do Instagram no login do Facebook; volte-a ao login do Instagram antes do rollback' if facebook.present?

    remove_column :channel_instagram, :page_id, if_exists: true
    remove_column :channel_instagram, :login, if_exists: true
  end
end
