# Registro durável das passagens de uma conversa (#1606, contrato fixado com o #1593 e o Agentes IA): quem passou para
# quem, quem pediu, quando e por quê, e quando voltou. Hoje a marca da entrega e a espera do robô somem justamente na
# entrega bem sucedida, e a IA relia "quero falar com alguém" já atendido (pingue-pongue).
#
# As pontas (de, para, pedida_por, devolvida_por) são polimórficas (User, Autonomia::Agents::Agent ou AgentBot) e
# guardam o nome daquele instante: o histórico não muda quando alguém troca de nome, e a linha sobrevive à pessoa ou
# ao agente apagados. O tipo (pessoa | ia) sai da classe.
class CreateCrmPassagens < ActiveRecord::Migration[7.2]
  def change # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    create_table :crm_passagens do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :card, foreign_key: { to_table: :crm_cards, on_delete: :nullify }, index: false
      t.references :pipeline, foreign_key: { to_table: :crm_pipelines, on_delete: :nullify }, index: false
      # Vazio quando ninguém estava com a conversa.
      t.string :de_type
      t.bigint :de_id
      t.string :de_nome
      t.string :para_type, null: false
      t.bigint :para_id, null: false
      t.string :para_nome
      # Quem pediu; vazio quando foi o sistema.
      t.string :pedida_por_type
      t.bigint :pedida_por_id
      t.string :pedida_por_nome
      t.string :motivo
      # Referência, sem chave estrangeira: a mensagem apagada não apaga nem bloqueia o histórico da passagem.
      t.bigint :message_id
      t.string :transfer_id
      t.datetime :em, null: false
      t.datetime :devolvida_em
      t.string :devolvida_por_type
      t.bigint :devolvida_por_id
      t.string :devolvida_por_nome
      t.timestamps

      t.index %i[conversation_id id], name: 'idx_crm_passagens_conversation'
      t.index :conversation_id, where: 'devolvida_em IS NULL', name: 'idx_crm_passagens_abertas'
      t.index %i[account_id created_at], name: 'idx_crm_passagens_account_created'
      t.index :card_id
      t.index :pipeline_id
    end
  end
end
