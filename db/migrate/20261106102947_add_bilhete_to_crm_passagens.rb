# Memória das IAs (#1601), PR 2: o bilhete da passagem. O código grava o bilhete na hora (fallback: falas do cliente e
# o que foi prometido); a IA só melhora o "o que o cliente quer", uma chamada por passagem, com reserva (status
# 'gerando' + reservado_em, que vence em 10 min) e no máximo 2 tentativas. Colunas nulas: passagem antiga fica sem bilhete.
class AddBilheteToCrmPassagens < ActiveRecord::Migration[7.2]
  def change
    change_table :crm_passagens, bulk: true do |t|
      t.jsonb :bilhete
      t.bigint :bilhete_ate_message_id
      t.string :bilhete_status
      t.datetime :bilhete_reservado_em
      t.datetime :bilhete_gerado_em
      t.string :bilhete_modelo
      t.integer :bilhete_tentativas, null: false, default: 0
    end
  end
end
