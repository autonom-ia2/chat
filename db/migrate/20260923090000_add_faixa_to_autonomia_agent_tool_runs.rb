# UMA EXECUÇÃO VIVA POR CONVERSA, FERRAMENTA E FAIXA (teste em produção de 23/09/2026, conversa 7057).
#
# O índice `idx_autonomia_tool_runs_active` garantia uma execução viva por (conversa, ferramenta), e o `open!`
# supersedia a anterior: o cliente que corrige um dado não gera duas cotações. Com residencial ao lado de auto
# isso virou defeito: pedir o seguro do apartamento com a cotação do carro rodando TROCOU a do carro, que já tinha
# 8 preços, e o cliente nunca recebeu o comparativo dela.
#
# A FAIXA é o que separa dois trabalhos da mesma ferramenta que não se substituem: em `cotar_seguro`, o produto
# (auto, residencial). Ferramenta sem faixa grava vazio e continua com uma execução viva por conversa, como antes.
# As linhas de `cotar_seguro` que já existem recebem o produto dos próprios argumentos (em branco é auto, como em
# `InsuranceQuote#produto`), para o pedido repetido e a leitura do resultado acharem a execução do produto certo.
#
# A troca do índice é atômica: a migration roda numa transação, e a tabela é pequena.
class AddFaixaToAutonomiaAgentToolRuns < ActiveRecord::Migration[7.2]
  def up
    add_column :autonomia_agent_tool_runs, :faixa, :string, null: false, default: ''
    execute(<<~SQL.squish)
      UPDATE autonomia_agent_tool_runs
      SET faixa = COALESCE(NULLIF(BTRIM(arguments ->> 'produto'), ''), 'auto')
      WHERE slug = 'cotar_seguro'
    SQL
    remove_index :autonomia_agent_tool_runs, name: 'idx_autonomia_tool_runs_active'
    add_index :autonomia_agent_tool_runs, [:conversation_id, :slug, :faixa], unique: true,
                                                                             where: "status IN ('pending', 'running')",
                                                                             name: 'idx_autonomia_tool_runs_active'
  end

  # A volta devolve o índice de uma execução viva por (conversa, ferramenta). Com auto e residencial vivos na mesma
  # conversa ele não seria criado: fica a mais nova, e a outra é trocada, como o `open!` de antes faria.
  def down
    remove_index :autonomia_agent_tool_runs, name: 'idx_autonomia_tool_runs_active'
    execute(<<~SQL.squish)
      UPDATE autonomia_agent_tool_runs r SET status = 'superseded', updated_at = now()
      WHERE r.status IN ('pending', 'running') AND EXISTS (
        SELECT 1 FROM autonomia_agent_tool_runs n
        WHERE n.conversation_id = r.conversation_id AND n.slug = r.slug AND n.status IN ('pending', 'running')
          AND (n.created_at, n.id) > (r.created_at, r.id))
    SQL
    add_index :autonomia_agent_tool_runs, [:conversation_id, :slug], unique: true,
                                                                     where: "status IN ('pending', 'running')",
                                                                     name: 'idx_autonomia_tool_runs_active'
    remove_column :autonomia_agent_tool_runs, :faixa
  end
end
