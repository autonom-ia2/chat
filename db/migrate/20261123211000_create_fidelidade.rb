# #3100 (F4 do épico #3095): o cartão fidelidade da conta e o cupom único por pessoa. Tudo tabela nova do fork, vazia:
# sem trava em tabela que já existe, sem job enfileirado, sem mexer em conta nenhuma.
#
# - fidelidade_programas: o cartão da conta (um por conta). Carimbos ou pontos, "a cada quanto" (em centavos, na moeda
#   do cartão), quantos a compra dá, a meta, o prêmio e a validade. `ligado_em` diz desde quando a compra conta (compra
#   de antes não dá carimbo; pausar e ligar de novo recomeça a contagem).
# - fidelidade_movimentos: o histórico, só acrescentado. Cada entrada guarda o que dela ainda não saiu (`restante`),
#   para vencer por ordem de chegada. A compra e o estorno de um card são únicos por pessoa e por vez (`vez`): o mesmo
#   card não dá carimbo duas vezes, e o card desfeito e ganho de novo é outra vez.
# - fidelidade_saldos: o saldo pronto de cada pessoa, para a ficha, o painel e o filtro. Muda na mesma transação do
#   movimento, com a linha travada.
# - fidelidade_cupons e fidelidade_cupom_codigos: o cupom da conta e o código de cada pessoa (um por pessoa e cupom).
#   O código é único na conta pela forma limpa (`codigo_limpo`: sem o hífen), a que o Conferir procura: digitado com ou
#   sem o hífen, acha o mesmo código.
#
# Chaves: contato em cascata (apagar a pessoa apaga o cartão e os códigos dela); conta e cartão sem cascata, como as
# outras tabelas da conta (a exclusão da conta, Autonomia::ExclusaoDaConta, apaga antes); quem fez (usuário) vira nulo
# quando o usuário sai. O contato tem índice nas tabelas com cascata, para apagar a pessoa não varrer a tabela.
class CreateFidelidade < ActiveRecord::Migration[7.2]
  def change
    criar_programas
    criar_movimentos
    criar_saldos
    criar_cupons
    criar_codigos
  end

  private

  def criar_programas
    create_table :fidelidade_programas do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :tipo, null: false
      t.bigint :a_cada_centavos, null: false
      t.string :moeda, null: false, default: 'BRL'
      t.integer :ganha, null: false
      t.integer :meta, null: false
      t.string :premio, limit: 80, null: false
      t.integer :validade_meses
      t.boolean :ligado, null: false, default: true
      t.datetime :ligado_em
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.timestamps
    end
  end

  def criar_movimentos
    create_table :fidelidade_movimentos do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :programa, null: false, foreign_key: { to_table: :fidelidade_programas }, index: false
      t.string :tipo, null: false
      t.integer :quantos, null: false
      t.integer :vez, null: false, default: 1
      t.string :origem_type
      t.bigint :origem_id
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.bigint :valor_centavos
      t.string :moeda
      t.string :motivo, limit: 60
      t.datetime :vence_em
      t.integer :restante, null: false, default: 0
      t.timestamps
      indices_dos_movimentos(t)
    end
  end

  # A compra e o estorno de um card são únicos por pessoa e por vez (ver o topo). O filtro do índice único vai em `OR`,
  # não em `IN`: é a forma que o Postgres devolve igual depois de ler o schema.rb.
  def indices_dos_movimentos(tabela)
    tabela.index %i[account_id], name: 'idx_fidelidade_movimentos_conta'
    tabela.index %i[contact_id created_at], name: 'idx_fidelidade_movimentos_pessoa'
    tabela.index %i[programa_id contact_id origem_type origem_id tipo vez],
                 unique: true, name: 'idx_fidelidade_movimentos_origem', where: "tipo = 'compra' OR tipo = 'estorno'"
    tabela.index %i[programa_id tipo created_at], name: 'idx_fidelidade_movimentos_programa_tipo'
    tabela.index %i[vence_em], name: 'idx_fidelidade_movimentos_a_vencer', where: 'restante > 0 AND vence_em IS NOT NULL'
  end

  def criar_saldos
    create_table :fidelidade_saldos do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :programa, null: false, foreign_key: { to_table: :fidelidade_programas }, index: false
      t.integer :saldo, null: false, default: 0
      t.timestamps
      t.index %i[programa_id contact_id], unique: true, name: 'idx_fidelidade_saldos_pessoa'
      t.index %i[programa_id saldo], name: 'idx_fidelidade_saldos_saldo'
      t.index %i[account_id], name: 'idx_fidelidade_saldos_conta'
    end
  end

  def criar_cupons
    create_table :fidelidade_cupons do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :nome, limit: 60, null: false
      t.string :oferta_tipo, null: false
      t.integer :oferta_valor
      t.string :oferta_texto, limit: 60
      t.string :moeda
      t.string :prefixo, limit: 8, null: false
      t.integer :validade_dias, null: false
      t.integer :limite_por_cliente, null: false, default: 1
      t.boolean :ligado, null: false, default: true
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.timestamps
      t.index %i[account_id created_at], name: 'idx_fidelidade_cupons_conta'
    end
  end

  def criar_codigos
    create_table :fidelidade_cupom_codigos do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :cupom, null: false, foreign_key: { to_table: :fidelidade_cupons }, index: false
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :codigo, limit: 20, null: false
      t.string :codigo_limpo, limit: 20, null: false
      t.datetime :enviado_em
      t.datetime :vale_ate
      t.integer :usos, null: false, default: 0
      t.datetime :usado_em
      t.references :usado_por, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.bigint :automacao_execucao_id
      t.timestamps
      t.index %i[account_id codigo_limpo], unique: true, name: 'idx_fidelidade_cupom_codigos_codigo'
      t.index %i[cupom_id contact_id], unique: true, name: 'idx_fidelidade_cupom_codigos_pessoa'
    end
  end
end
