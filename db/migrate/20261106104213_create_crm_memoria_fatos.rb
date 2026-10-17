# Memória das IAs (#1601), PR 3: os fatos do pedido e do cliente com procedência.
#
# crm_memoria_chaves: o catálogo fechado, uma linha por (conta, modelo do atributo, chave). Nasce dos campos
# personalizados da conta (contato, card, conversa) e das chaves do sistema. A IA não cria chave.
#
# crm_memoria_fatos: bitemporal. A versão antiga expira (expirado_em), não é apagada. Fonte e status vêm do código, nunca
# do modelo; o CHECK garante no banco que só ferramenta, sistema ou pessoa confirmam. Um vigente por (escopo, chave,
# item) pelo índice único parcial (decisões acumulam e ficam fora dele). FK com CASCADE no contato e no card: apagar
# o contato (ou o card) apaga a memória dele no banco.
#
# Também: o card em foco na abertura de uma execução de ferramenta (W5) e, na telemetria de custo, o agente e o card
# (adendo 9; colunas nulas, sem índice, numa tabela quente).
class CreateCrmMemoriaFatos < ActiveRecord::Migration[7.2]
  def change
    create_chaves
    create_fatos
    add_column :autonomia_agent_tool_runs, :card_id, :bigint
    add_column :crm_ai_usage_events, :agent_id, :bigint
    add_column :crm_ai_usage_events, :card_id, :bigint
  end

  private

  def create_chaves
    create_table :crm_memoria_chaves do |t|
      t.bigint :account_id, null: false
      t.string :attribute_model, null: false
      t.string :chave, null: false
      t.string :rotulo
      t.string :nivel, null: false
      t.integer :cardinalidade, null: false, default: 1
      t.boolean :item_natural, null: false, default: false
      t.boolean :identidade, null: false, default: false
      t.boolean :obrigatoria, null: false, default: false
      t.integer :validade_dias
      t.timestamps
    end
    add_index :crm_memoria_chaves, %i[account_id attribute_model chave], unique: true, name: 'idx_crm_memoria_chaves_unica'
    add_foreign_key :crm_memoria_chaves, :accounts, on_delete: :cascade
  end

  def create_fatos # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    create_table :crm_memoria_fatos do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, null: false
      t.string :escopo, null: false
      t.bigint :card_id
      t.bigint :conversation_id
      t.string :tipo, null: false
      t.string :chave, null: false
      t.string :item_ref, null: false, default: ''
      t.text :valor
      t.jsonb :valor_json
      t.string :fonte, null: false
      t.string :status, null: false
      t.string :situacao, null: false
      t.bigint :divergente_de_id
      t.bigint :prova_message_ids, array: true, null: false, default: []
      t.text :prova_trecho
      t.datetime :valido_desde, null: false
      t.datetime :vence_em
      t.datetime :registrado_em, null: false
      t.datetime :expirado_em
      t.integer :versao, null: false, default: 1
      t.bigint :substitui_id
      t.boolean :travado, null: false, default: false
      t.bigint :travado_por_user_id
      t.string :gerado_por, null: false
      t.string :idempotency_key
      t.timestamps
    end
    add_fatos_checks
    add_fatos_indexes
    add_foreign_key :crm_memoria_fatos, :contacts, on_delete: :cascade
    add_foreign_key :crm_memoria_fatos, :crm_cards, column: :card_id, on_delete: :cascade
  end

  def add_fatos_checks
    add_check_constraint :crm_memoria_fatos, "status IN ('alegado', 'confirmado')", name: 'crm_memoria_fatos_status'
    add_check_constraint :crm_memoria_fatos,
                         "status <> 'confirmado' OR fonte IN ('ferramenta_resultado', 'sistema', 'pessoa_corrigiu')",
                         name: 'crm_memoria_fatos_so_codigo_confirma'
    add_check_constraint :crm_memoria_fatos,
                         "(escopo = 'card' AND card_id IS NOT NULL AND conversation_id IS NULL) OR " \
                         "(escopo = 'conversa' AND conversation_id IS NOT NULL AND card_id IS NULL) OR " \
                         "(escopo = 'contato' AND card_id IS NULL AND conversation_id IS NULL)",
                         name: 'crm_memoria_fatos_escopo'
    add_check_constraint :crm_memoria_fatos,
                         "cardinality(prova_message_ids) > 0 OR fonte IN ('pessoa_corrigiu', 'sistema', 'ferramenta_resultado')",
                         name: 'crm_memoria_fatos_prova'
    add_check_constraint :crm_memoria_fatos, 'char_length(valor) <= 300 AND char_length(prova_trecho) <= 300',
                         name: 'crm_memoria_fatos_tamanho'
  end

  def add_fatos_indexes
    add_index :crm_memoria_fatos, 'account_id, escopo, COALESCE(card_id, 0), COALESCE(conversation_id, 0), contact_id, chave, item_ref',
              unique: true, name: 'idx_crm_memoria_fatos_vigente',
              where: "situacao = 'vigente' AND expirado_em IS NULL AND tipo <> 'decisao'"
    add_index :crm_memoria_fatos, %i[account_id card_id], name: 'idx_crm_memoria_fatos_card', where: 'expirado_em IS NULL'
    add_index :crm_memoria_fatos, %i[account_id contact_id escopo], name: 'idx_crm_memoria_fatos_contato'
    add_index :crm_memoria_fatos, :idempotency_key, unique: true, where: 'idempotency_key IS NOT NULL'
    add_index :crm_memoria_fatos, :prova_message_ids, using: :gin, name: 'idx_crm_memoria_fatos_provas'
  end
end
