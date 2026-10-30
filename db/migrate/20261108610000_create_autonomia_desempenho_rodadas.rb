# Leitura automática diária do painel de desempenho (#2301, épico #2226): uma linha por rodada de leitura de um
# agente (sujeito) numa conta.
#
# - `corte_em`: até onde a rodada leu (as mensagens até este instante). O painel mostra "Lido até" com o corte da
#   última rodada `ok` ou `teto`.
# - `piso_em`: a conversa que nunca foi lida entra só com mensagem depois daqui. Na primeira rodada é a última
#   mensagem lida pela carga; as rodadas seguintes repetem o mesmo piso, para a conversa que ficou pendente (teto,
#   limite da rodada) não sumir da fila.
# - `status`: rodando | ok | teto (parou no teto diário de gasto) | sem_ia (a conta não tem a própria chave de IA) |
#   chave_recusada (a IA recusou a chave da conta: 401 ou 403) | erro (a rodada caiu no meio).
# - `conversas_lidas` e `conversas_pendentes`: o que a rodada leu e o que ficou para a próxima.
# - `pendente_desde`: com pendentes, a mensagem nova mais antiga entre elas, gravada ao fechar. O painel mostra
#   "Lido até" logo antes dela (tudo antes foi lido), sem refazer a consulta da fila.
# - `custo_usd`: o gasto da rodada, somado do consumo gravado pela chamada.
#
# Tabela nova e vazia: o índice nasce junto. Sem `sujeito_type` no índice, como em autonomia_desempenho_procuras: o
# strong_migrations recusa índice não único com mais de 3 colunas, e o id do sujeito já estreita.
# Apagar a conta apaga as rodadas pela chave estrangeira; o Autonomia::ExclusaoDaConta também lista a tabela.
class CreateAutonomiaDesempenhoRodadas < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_desempenho_rodadas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :sujeito_type, null: false
      t.bigint :sujeito_id, null: false
      t.datetime :corte_em, null: false
      t.datetime :piso_em, null: false
      t.datetime :iniciada_em, null: false
      t.datetime :terminada_em
      t.string :status, null: false
      t.integer :conversas_lidas, null: false, default: 0
      t.integer :conversas_pendentes, null: false, default: 0
      t.datetime :pendente_desde
      t.decimal :custo_usd, precision: 12, scale: 6, null: false, default: 0
      t.string :lote, null: false
      t.timestamps
    end
    add_index :autonomia_desempenho_rodadas, %i[account_id sujeito_id iniciada_em], name: 'idx_autonomia_desempenho_rodadas_inicio'
    add_checks
  end

  private

  def add_checks
    add_check_constraint :autonomia_desempenho_rodadas, "sujeito_type::text = ANY ('{agente,robo}'::text[])",
                         name: 'autonomia_desempenho_rodadas_sujeito'
    add_check_constraint :autonomia_desempenho_rodadas, "status::text = ANY ('{rodando,ok,teto,sem_ia,chave_recusada,erro}'::text[])",
                         name: 'autonomia_desempenho_rodadas_status'
  end
end
