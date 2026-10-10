# Identidade visual por conta (#1076): kits de marca usados pelo e-mail com IA. Tabela do fork (aditiva).
# `appearance` guarda paleta com papéis, fontes, logo_url, redes e rodapé — o formato é validado por
# BrandKits::Appearance. Um único kit padrão por conta entre os não arquivados; nome único (sem caixa)
# entre os não arquivados, para um kit arquivado não travar o nome.
class CreateBrandKits < ActiveRecord::Migration[7.2]
  def change
    create_table :brand_kits do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :name, null: false
      t.boolean :is_default, null: false, default: false
      t.datetime :archived_at
      t.jsonb :appearance, null: false, default: {}
      t.string :source_url
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :brand_kits, :account_id, unique: true, where: 'is_default AND archived_at IS NULL',
                                        name: 'idx_brand_kits_one_default_per_account'
    add_index :brand_kits, 'account_id, lower(name)', unique: true, where: 'archived_at IS NULL',
                                                      name: 'idx_brand_kits_live_name_per_account'
  end
end
