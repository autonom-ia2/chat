# Decisor (#858), etapa 2: o Decisor lê o que declara (mensagens, contato, conversa, card, empresa) e
# também serve às automações de etapa do CRM, onde o alvo é o card e pode não haver mensagem.
#
# Só aditiva: `leituras` nasce vazia (= o que a etapa 1 lia), e a decisão passa a aceitar um card no
# lugar da mensagem. A decisão sobre um card é única por (decisor, card, gatilho) — o gatilho é a marca
# da entrada/saída de etapa —, como a da conversa é única por mensagem.
class DecisorLeQualquerAlvo < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_decisores, :leituras, :jsonb, null: false, default: []

    change_column_null :autonomia_decisor_decisoes, :conversation_id, true
    change_column_null :autonomia_decisor_decisoes, :message_id, true
    add_reference :autonomia_decisor_decisoes, :crm_card, foreign_key: { to_table: :crm_cards, on_delete: :cascade }
    add_column :autonomia_decisor_decisoes, :gatilho, :string
    add_index :autonomia_decisor_decisoes, [:decisor_id, :crm_card_id, :gatilho],
              unique: true, where: 'gatilho IS NOT NULL', name: 'idx_autonomia_decisoes_por_gatilho'
  end
end
