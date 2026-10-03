# A conversa com o Guia e o registro de cada pedido (#861).
#
# Até aqui a conversa vivia só na memória do navegador: recarregar a página
# apagava tudo, e o que o Guia leu, chamou e decidiu era uma linha de log. Uma
# conversa é de UMA pessoa numa conta; um turno é um pedido (o mesmo id do
# Redis), com a pergunta, a resposta e o diagnóstico para o time investigar.
#
# Guardado por 30 dias depois da última mensagem (`Conversa::RETENCAO`): o texto
# pode ter dado pessoal de cliente, e passado o prazo de investigar ele não tem
# por que continuar no banco.
class CreateAutonomiaGuideConversations < ActiveRecord::Migration[7.2]
  def change
    criar_conversas
    criar_turnos
  end

  private

  def criar_conversas
    create_table :autonomia_guide_conversations do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :titulo, limit: 120, null: false, default: ''
      t.timestamps
    end
    add_index :autonomia_guide_conversations, [:account_id, :user_id, :updated_at],
              name: 'idx_autonomia_guide_conversations_dono'
    add_index :autonomia_guide_conversations, :updated_at
  end

  def criar_turnos
    create_table :autonomia_guide_turns do |t|
      t.references :conversation, null: false, index: false,
                                  foreign_key: { to_table: :autonomia_guide_conversations, on_delete: :cascade }
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.uuid :pedido_id, null: false
      t.text :pergunta, null: false, default: ''
      t.jsonb :anexos, null: false, default: []
      t.string :tela
      colunas_do_desfecho(t)
      t.timestamps
    end
    indexar_turnos
  end

  # O que voltou do pedido: a resposta, as telas e artigos, a ação proposta e o
  # que o Guia fez, e o registro de diagnóstico.
  def colunas_do_desfecho(tabela)
    tabela.string :status, null: false, default: 'pending'
    tabela.text :resposta
    tabela.jsonb :navegacoes, null: false, default: []
    tabela.jsonb :artigos, null: false, default: []
    tabela.jsonb :acao
    tabela.string :acao_estado
    tabela.string :acao_resultado
    tabela.references :execution, foreign_key: { to_table: :autonomia_guide_executions, on_delete: :nullify }
    tabela.jsonb :passos, null: false, default: []
    tabela.jsonb :diagnostico, null: false, default: {}
  end

  # A conversa em ordem, o pedido do Redis (a chave da investigação) e a conta no tempo.
  def indexar_turnos
    add_index :autonomia_guide_turns, [:conversation_id, :created_at]
    add_index :autonomia_guide_turns, :pedido_id, unique: true
    add_index :autonomia_guide_turns, [:account_id, :created_at]
  end
end
