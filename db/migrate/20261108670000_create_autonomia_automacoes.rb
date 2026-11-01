# Automação livre (#2414, F2 #2452): as 4 tabelas do motor novo, como no ADR-001 do épico (seção 2.3).
# Ficam sem uso até a F3 (o motor).
# - automacoes: a automação da conta. Nasce desligada; `ligada_por_id` é quem ligou (D1: o motor age como essa pessoa).
# - versoes: a receita de cada salvamento. Imutável: salvar cria a próxima, e quem já está no meio segue na antiga.
# - execucoes: uma automação rodando para um alvo (conversa, card ou contato). Uma só aberta por automação, alvo e
#   gatilho: o índice único vale enquanto `finalizada_em` é nula, e um CHECK amarra `finalizada_em` ao estado terminal.
# - registros: uma linha por passo, para o histórico. Retenção de 30 dias (Autonomia::Automacao::LimparRegistrosJob).
class CreateAutonomiaAutomacoes < ActiveRecord::Migration[7.2]
  ABERTA = 'finalizada_em IS NULL'.freeze
  # Estado terminal e finalizada_em andam juntos também fora do modelo (update_all): terminal sem finalizada_em deixaria a
  # execução aberta para o índice único e travaria o alvo. Mesma lista de Autonomia::Automacao::Execucao::TERMINAIS.
  # Escrita na forma que o Postgres devolve, com literais text: `estado IN (...)` sai do dump com cast de varchar, e esse
  # texto, carregado de novo pelo schema.rb, vira outra expressão (a CI das migrations compara as duas).
  FINALIZADA = "((estado)::text = ANY (ARRAY['concluida'::text, 'falhou'::text, 'interrompida'::text, 'parada'::text])) " \
               '= (finalizada_em IS NOT NULL)'.freeze

  def change
    criar_automacoes
    criar_versoes
    ligar_versao_ativa
    criar_execucoes
    criar_registros
  end

  private

  def criar_automacoes
    create_table :autonomia_automacoes do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :nome, null: false
      t.boolean :ativa, null: false, default: false
      t.string :origem, null: false
      t.bigint :versao_ativa_id
      t.references :ligada_por, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
      t.index [:account_id, :ativa], name: 'idx_autonomia_automacoes_ligadas'
      t.index :versao_ativa_id
    end
  end

  def criar_versoes
    create_table :autonomia_automacao_versoes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :automacao, null: false, foreign_key: { to_table: :autonomia_automacoes }, index: false
      t.integer :numero, null: false
      t.jsonb :receita, null: false, default: {}
      t.string :digest, null: false
      t.references :autor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false
      t.index [:automacao_id, :numero], unique: true, name: 'idx_autonomia_automacao_versoes_numero'
    end
  end

  # A versão ativa aponta para a tabela de baixo; criada depois dela. SET NULL para a exclusão da conta apagar as
  # versões antes das automações sem esbarrar nesta chave. safety_assured: as duas tabelas acabaram de nascer, vazias,
  # na mesma transação; não há linha a validar nem escrita a bloquear.
  def ligar_versao_ativa
    safety_assured do
      add_foreign_key :autonomia_automacoes, :autonomia_automacao_versoes, column: :versao_ativa_id, on_delete: :nullify
    end
  end

  def criar_execucoes
    create_table :autonomia_automacao_execucoes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :automacao, null: false, foreign_key: { to_table: :autonomia_automacoes }
      t.references :versao, null: false, foreign_key: { to_table: :autonomia_automacao_versoes }
      t.references :alvo, polymorphic: true, null: false
      t.string :chave_gatilho, null: false
      t.string :cursor
      t.datetime :due_at
      t.string :estado, null: false, default: 'andando'
      t.datetime :finalizada_em
      t.jsonb :cadeia, null: false, default: []
      t.integer :profundidade, null: false, default: 0
      t.integer :tentativas, null: false, default: 0
      t.datetime :travada_em
      t.timestamps
      t.index [:automacao_id, :alvo_type, :alvo_id, :chave_gatilho], unique: true, where: ABERTA, name: 'idx_autonomia_automacao_execucoes_abertas'
      t.index :due_at, where: ABERTA, name: 'idx_autonomia_automacao_execucoes_esperando'
      t.check_constraint FINALIZADA, name: 'chk_autonomia_automacao_execucoes_finalizada'
    end
  end

  def criar_registros
    create_table :autonomia_automacao_registros do |t|
      t.references :account, null: false, foreign_key: true
      t.references :automacao, null: false, foreign_key: { to_table: :autonomia_automacoes }, index: false
      t.references :execucao, null: false, foreign_key: { to_table: :autonomia_automacao_execucoes }, index: false
      t.string :passo, null: false
      t.string :resultado, null: false
      t.string :motivo
      t.jsonb :dados, null: false, default: {}
      t.datetime :created_at, null: false
      t.index [:execucao_id, :created_at], name: 'idx_autonomia_automacao_registros_execucao'
      t.index [:automacao_id, :created_at], name: 'idx_autonomia_automacao_registros_automacao'
      t.index :created_at
    end
  end
end
