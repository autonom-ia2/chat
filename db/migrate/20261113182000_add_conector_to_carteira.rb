# E7 (#2900), parte 0: o que a carteira guarda para trazer os seguros pelo conector (Agger). Nada lê nem grava aqui
# ainda: a sincronização, a tela e a parcela atrasada vêm nos PRs seguintes, atrás de Carteira::Acesso.
# - `carteira_apolices.origem_ref`: a referência do registro na origem (o conector). É ela que faz a busca de todo dia
#   achar o mesmo seguro em vez de criar outro. Nula para o que veio de planilha, PDF ou à mão.
# - `carteira_apolices.parcela_aberta_em`: o dia em que a parcela em aberto venceu, como o conector informa (selo e
#   grupo "parcela atrasada"). Nula quando não há parcela em aberto ou a origem não informa.
# - `carteira_renovacao_configs.busca_diaria`: a conta quer (ou não) que a busca no conector rode todo dia. Desligada
#   por padrão: só liga quando a corretora liga o conector.
#
# Índice: único parcial [account_id, origem, origem_ref] WHERE origem_ref IS NOT NULL. Começa por account_id (a mesma
# referência em duas contas são dois seguros) e só cobre as linhas do conector. Entra CONCURRENTLY, fora de transação,
# e não trava a escrita na carteira. Um CREATE INDEX CONCURRENTLY que cai no meio deixa o índice INVALID, e o
# `if_not_exists` o aceitaria como pronto: por isso o inválido é tirado antes de criar de novo. Como nenhuma linha tem
# `origem_ref` ainda, o índice nasce vazio e não pode falhar por duplicata.
#
# Travas: cada ADD COLUMN pega ACCESS EXCLUSIVE na tabela só pelo instante. As colunas de carteira_apolices são nulas;
# `busca_diaria` tem padrão constante, que o Postgres guarda no catálogo sem reescrever a tabela (produção roda o 18).
# Tudo com o lock_timeout curto do strong_migrations (5 s, 3 tentativas). Cada passo pode rodar de novo sem erro se o
# deploy cair no meio.
#
# Só aditiva: o código anterior não conhece as colunas, e a única não nula tem padrão.
#
# Rollback: o `down` tira o índice e as três colunas (nada mais depende deles).
class AddConectorToCarteira < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE_DA_ORIGEM = 'idx_carteira_apolices_origem_ref'.freeze
  COLUNAS_DA_APOLICE = [[:origem_ref, :string], [:parcela_aberta_em, :date]].freeze

  def up
    COLUNAS_DA_APOLICE.each { |coluna, tipo| add_column :carteira_apolices, coluna, tipo, if_not_exists: true }
    add_column :carteira_renovacao_configs, :busca_diaria, :boolean, null: false, default: false, if_not_exists: true
    criar_o_indice_da_origem
  end

  def down
    remove_index :carteira_apolices, name: INDICE_DA_ORIGEM, algorithm: :concurrently, if_exists: true
    remove_column :carteira_renovacao_configs, :busca_diaria, if_exists: true
    COLUNAS_DA_APOLICE.map(&:first).each { |coluna| remove_column :carteira_apolices, coluna, if_exists: true }
  end

  private

  def criar_o_indice_da_origem
    colunas = %i[account_id origem origem_ref]
    invalido = index_exists?(:carteira_apolices, colunas, name: INDICE_DA_ORIGEM, valid: false)
    remove_index :carteira_apolices, name: INDICE_DA_ORIGEM, algorithm: :concurrently if invalido
    add_index :carteira_apolices, colunas, unique: true, where: 'origem_ref IS NOT NULL', name: INDICE_DA_ORIGEM,
                                           algorithm: :concurrently, if_not_exists: true
  end
end
