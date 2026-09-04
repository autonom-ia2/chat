class CreateAutonomiaAgentToolRuns < ActiveRecord::Migration[7.2]
  def change
    create_runs_table
    add_indexes
  end

  private

  def create_runs_table
    create_table :autonomia_agent_tool_runs do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.bigint :autonomia_agent_id, null: false
      # A conversa é o destino da entrega. Sem ela não existe execução assíncrona: a ferramenta
      # assíncrona só é aceita no caminho de atendimento (Operate), nunca no Testar/Copiloto.
      t.bigint :conversation_id, null: false
      # Guardado para revalidar o contrato inteiro (mesma caixa, mesmo agente) na hora de publicar,
      # em vez de confiar num agent_id solto vindo do argumento do job.
      t.bigint :agent_inbox_id
      t.string :slug, null: false
      # pending  -> registrada no turno, ainda não despachada (o turno pode morrer e ela é descartada)
      # running  -> despachada; o job está submetendo/consultando
      # done | failed | superseded | discarded | blocked -> terminais
      t.string :status, null: false, default: 'pending'
      # Chave estável da execução. É ela (com o número da entrega) que carimba a mensagem publicada
      # e dá idempotência a retry de Sidekiq.
      t.string :execution_key, null: false
      # Argumentos que o modelo montou. Ficam AQUI e não no payload do job de propósito: no Redis
      # eles sobreviveriam no retry/dead set (visível em /monitoring/sidekiq) sem TTL nosso. No banco
      # têm a mesma exposição do texto que o cliente já digitou em `messages.content`.
      t.jsonb :arguments, null: false, default: {}
      # O que a ferramenta devolveu do `start` (ex.: id da cotação no portal). Nunca credencial —
      # a ferramenta resolve a conexão sozinha a cada consulta.
      t.jsonb :handle, null: false, default: {}
      # Quantas entregas já foram publicadas. Também é o índice da próxima.
      t.integer :sequence, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      # Mensagem incoming que originou o turno + quantos pedaços a resposta daquele turno vai
      # entregar. Serve para a entrega assíncrona NÃO se intercalar no meio da cadeia humanizada.
      t.bigint :origin_message_id
      t.integer :expected_chunks, null: false, default: 0
      # O turno ficou em silêncio (sinal de silêncio, falha de IA, porta de engajamento)? Então quem
      # avisa o cliente de que a consulta começou é o job, não o modelo.
      t.boolean :notify_customer, null: false, default: false
      # Teto de tempo de parede. É o que sobrevive a re-enfileiramento perdido, diferente da contagem.
      t.datetime :expires_at
      t.string :failure_code
      t.timestamps
    end
  end

  def add_indexes
    add_index :autonomia_agent_tool_runs, :execution_key, unique: true,
                                                          name: 'idx_autonomia_tool_runs_execution_key'
    # UMA execução viva por (conversa, ferramenta). Uma chamada nova SUPERSEDE a anterior — o cliente
    # que corrige um dado ("na verdade é 2019") não pode gerar duas cotações concorrentes. É o mesmo
    # last-writer-wins do resto do namespace (sync_token, build_token, debounce).
    add_index :autonomia_agent_tool_runs, [:conversation_id, :slug], unique: true,
                                                                     where: "status IN ('pending', 'running')",
                                                                     name: 'idx_autonomia_tool_runs_active'
    add_index :autonomia_agent_tool_runs, [:conversation_id, :created_at],
              name: 'idx_autonomia_tool_runs_conversation'
    add_index :autonomia_agent_tool_runs, [:account_id, :slug, :created_at],
              name: 'idx_autonomia_tool_runs_account_slug'
  end
end
