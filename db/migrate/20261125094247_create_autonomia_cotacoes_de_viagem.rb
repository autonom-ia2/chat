# Agente pronto Seguro Viagem Universal (#3211): a cotação de viagem guardada por conversa, para a proposta sair com o
# preço e o plano que o cliente viu. Tabela nova e vazia: nenhuma trava em tabela que já existe, nenhum job enfileirado.
#
# `pedido` guarda os nossos parâmetros já conferidos e o pedido enviado à seguradora; `planos`, a lista de planos
# devolvida; `proposta`, a proposta emitida (nula até emitir).
#
# Chaves: conversa e agente em cascata; conta sem cascata, como as outras tabelas da conta: a exclusão da conta
# (Autonomia::ExclusaoDaConta) apaga as linhas antes do DELETE da conta. O índice [conversation_id, id] cobre a chave da
# conversa pela primeira coluna e serve a busca da última cotação.
class CreateAutonomiaCotacoesDeViagem < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_cotacoes_de_viagem do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :conversation, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :autonomia_agent, null: false, index: true,
                                     foreign_key: { to_table: :autonomia_agents, on_delete: :cascade }
      t.string :id_cotacao, null: false
      t.jsonb :pedido, null: false, default: {}
      t.jsonb :planos, null: false, default: []
      t.jsonb :proposta
      t.timestamps
    end
    add_index :autonomia_cotacoes_de_viagem, %i[conversation_id id]
  end
end
