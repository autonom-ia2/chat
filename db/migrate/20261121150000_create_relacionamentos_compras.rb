# #3097 (F1 do épico #3095): o resumo das compras de cada pessoa e o grupo de compra dela.
#
# A compra é o card ganho num funil de Vender (inclusive o arquivado depois de ganho). Uma linha por pessoa que já
# comprou; quem nunca comprou não tem linha. A linha guarda o que a lista, a ficha e o gatilho leem sem somar os cards a
# cada pedido:
# - `quantas`, `primeira_em`, `ultima_em`: quantas compras e as datas da primeira e da última (closed_at do card);
# - `total_brl_cents`: o total em reais, que filtra ("total acima de") e ordena ("quem mais comprou");
# - `por_moeda`: [{ moeda, total_cents, quantas }]; moedas diferentes não se somam;
# - `grupo` e `grupo_desde`: o grupo de compra de agora (Relacionamentos::Compras::Grupo) e desde quando ela está nele.
#   É o grupo guardado que diz "entrou no grupo" para a automação.
#
# Quem escreve: Relacionamentos::Compras::Recalcular, no card ganho (ou que deixou de ser) e na rotina diária.
#
# Chaves: contato em cascata (apagar a pessoa apaga o resumo dela); conta sem cascata, como as outras tabelas da conta:
# a exclusão da conta (Autonomia::ExclusaoDaConta) apaga as linhas antes do DELETE da conta. Os índices começam pela
# conta, então account_id não ganha índice próprio. Tabela nova e vazia: sem travas. O preenchimento sai da migration
# seguinte, num job.
class CreateRelacionamentosCompras < ActiveRecord::Migration[7.2]
  def change
    create_table :relacionamentos_compras do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :quantas, null: false
      t.datetime :primeira_em, null: false
      t.datetime :ultima_em, null: false
      t.bigint :total_brl_cents, null: false, default: 0
      t.jsonb :por_moeda, null: false, default: []
      t.string :grupo, null: false
      t.datetime :grupo_desde, null: false
      t.timestamps
      t.index %i[account_id grupo], name: 'idx_relacionamentos_compras_conta_grupo'
      t.index %i[account_id ultima_em], name: 'idx_relacionamentos_compras_conta_ultima'
      t.index %i[account_id total_brl_cents], name: 'idx_relacionamentos_compras_conta_total'
    end
  end
end
