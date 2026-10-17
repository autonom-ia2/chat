# Memória das IAs (#1601), PR 1: quem escreveu cada mensagem e se ela chegou ao cliente, calculado pelo código
# (Crm::Memoria::Origem), e a configuração da conta (robôs de fora que usam login de pessoa, caixas fora da memória).
#
# Sem FK para `messages` de propósito (não acopla à tabela do Chatwoot). O contato tem FK com ON DELETE CASCADE: apagar
# o contato apaga a autoria das mensagens dele no banco, mesmo num delete cru. A mescla de contatos move as linhas
# antes do destroy (ContactMergeAction#merge_crm_memoria).
class CreateCrmMensagemOrigens < ActiveRecord::Migration[7.2]
  def change
    create_origens
    create_config
  end

  private

  def create_origens # rubocop:disable Metrics/MethodLength
    create_table :crm_mensagem_origens do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :contact_id, null: false
      t.bigint :message_id, null: false
      t.string :autor_tipo, null: false
      t.string :autor_ref_type
      t.bigint :autor_ref_id
      t.boolean :foi_ao_cliente, null: false, default: false
      t.bigint :duplicata_de_message_id
      t.boolean :indisponivel, null: false, default: false
      t.boolean :sem_conteudo, null: false, default: false
      t.boolean :encaminhada, null: false, default: false
      t.string :conteudo_hash
      t.string :regra, null: false
      t.integer :classificador_versao, null: false
      t.bigint :corrigido_por_user_id
      t.timestamps
    end
    add_index :crm_mensagem_origens, :message_id, unique: true
    add_index :crm_mensagem_origens, %i[account_id conversation_id message_id], name: 'idx_crm_mensagem_origens_conversa'
    add_index :crm_mensagem_origens, %i[account_id contact_id], name: 'idx_crm_mensagem_origens_contato'
    add_foreign_key :crm_mensagem_origens, :contacts, on_delete: :cascade
  end

  def create_config
    create_table :crm_memoria_configs do |t|
      t.bigint :account_id, null: false
      t.bigint :usuarios_robo_ids, array: true, null: false, default: []
      t.bigint :caixas_excluidas, array: true, null: false, default: []
      t.timestamps
    end
    add_index :crm_memoria_configs, :account_id, unique: true
    add_foreign_key :crm_memoria_configs, :accounts, on_delete: :cascade
  end
end
