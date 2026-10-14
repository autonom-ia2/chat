# Multifunil 6a (#1146): campos próprios de cada card. Duas cotações do mesmo cliente guardam valores separados (a placa
# do Onix não é a do HB20). Os campos são definidos pelo admin em Atributos (tipo "card", attribute_model 3).
# jsonb com default constante: no Postgres 11+ é só metadado, sem reescrever a tabela.
class AddCustomAttributesToCrmCards < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_cards, :custom_attributes, :jsonb, default: {}, null: false
  end
end
