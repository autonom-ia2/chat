# Página do Facebook de uma conta (#2195, comum ao #2197). O webhook de Página chega só com o page_id: esta tabela diz de
# que conta (ou contas) ela é. Fica cheia quando uma tela lê as Páginas com o token do cliente (remember!).
# `leadgen_receiving` (Formulários, #2195) e `feed_receiving` (comentários, #2197): o app assinou aquele campo na Página.
class Crm::MetaAdsPage < ApplicationRecord
  self.table_name = 'crm_meta_ads_pages'

  NAME_LIMIT = 255

  belongs_to :account

  validates :page_id, presence: true, uniqueness: { scope: :account_id }

  scope :leadgen_receiving, -> { where(leadgen_receiving: true) }
  scope :feed_receiving, -> { where(feed_receiving: true) }

  # A mesma Página pode estar em mais de uma conta.
  def self.account_ids_for(page_id)
    where(page_id: page_id.to_s).distinct.pluck(:account_id)
  end

  # pages: [{ 'id' =>, 'name' => }] como a Graph devolve em me/accounts. Guarda id e nome; não apaga a Página que sumiu
  # da lista (a pessoa pode ter tirado o acesso só por um tempo) nem mexe no que já foi assinado. Leitura sem nome (a
  # Graph pode não devolver) cria a Página sem nome, mas não apaga o nome que já estava guardado.
  # Só id e nome, validados aqui; upsert/insert evitam a corrida de duas leituras da mesma Página ao mesmo tempo.
  # rubocop:disable Rails/SkipsModelValidations
  def self.remember!(account, pages)
    named, unnamed = remember_rows(account, pages).partition { |row| row[:name] }
    upsert_all(named, unique_by: %i[account_id page_id], update_only: [:name]) if named.any?
    insert_all(unnamed, unique_by: %i[account_id page_id]) if unnamed.any?
  end
  # rubocop:enable Rails/SkipsModelValidations

  # O id da Página é número (a Graph manda como texto); outro tipo é lixo e fica fora.
  def self.remember_rows(account, pages)
    rows = Array(pages).filter_map do |page|
      next unless page.is_a?(Hash) && (page['id'].is_a?(String) || page['id'].is_a?(Integer)) && page['id'].to_s.present?

      { account_id: account.id, page_id: page['id'].to_s, name: page['name'].to_s.first(NAME_LIMIT).presence }
    end
    rows.uniq { |row| row[:page_id] }
  end
  private_class_method :remember_rows
end
