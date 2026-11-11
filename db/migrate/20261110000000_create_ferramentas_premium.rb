# Vitrine de ferramentas prontas, F7 (#2858): as consultas Premium, pagas, à BigDataCorp.
# - `autonomia_ferramentas_premium_consultas`: a telemetria de cada consulta, para gerar a cobrança na fatura (decisão
#   do Rodrigo, 10/11: sem crédito pré-pago e sem cobrança automática). Uma linha por consulta: conta, card, dataset,
#   custo, preço, grátis ou cobrada, resultado, dia e se veio do cache. Nunca o valor consultado (CNPJ, CPF, placa).
# - `autonomia_ferramentas_premium_saldos`: quantas consultas cada conta já usou em cada card NO MÊS, para as 20 grátis
#   que renovam todo mês (decisão do Rodrigo, 11/11). Uma linha por conta, card e mês (o 1º dia do mês, no fuso da conta),
#   somada por SQL atômico.
# Só aditiva: duas tabelas novas. Nada é lido sem a flag `agente_ferramentas_prontas_premium`. O down remove as duas.
class CreateFerramentasPremium < ActiveRecord::Migration[7.2]
  def change
    criar_consultas
    criar_saldos
  end

  private

  def criar_consultas
    create_table :autonomia_ferramentas_premium_consultas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :autonomia_agent_id
      t.string :fonte, null: false
      t.string :consulta, null: false
      t.string :dataset, null: false
      t.date :dia, null: false
      t.string :resultado, null: false
      t.string :cobranca, null: false
      t.boolean :do_cache, null: false, default: false
      t.integer :numero
      t.decimal :custo, precision: 10, scale: 4, null: false, default: 0
      t.decimal :preco, precision: 10, scale: 4, null: false, default: 0
      t.string :motivo
      t.string :id_na_fonte
      t.timestamps
    end
    add_index :autonomia_ferramentas_premium_consultas, %i[account_id fonte dia], name: 'idx_premium_consultas_conta_fonte_dia'
    add_index :autonomia_ferramentas_premium_consultas, :dia, name: 'idx_premium_consultas_dia'
  end

  def criar_saldos
    create_table :autonomia_ferramentas_premium_saldos do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :fonte, null: false
      t.date :mes, null: false
      t.integer :contadas, null: false, default: 0
      t.timestamps
    end
    add_index :autonomia_ferramentas_premium_saldos, %i[account_id fonte mes], unique: true, name: 'idx_premium_saldos_conta_fonte_mes'
  end
end
