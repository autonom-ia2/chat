# E8 (#2901): as três escolhas da cotação da renovação, por conta, e a caixa por onde as mensagens saem.
# - `quem_cota`: `robo` (o robô cota sozinho), `lia` (o robô cota e a Lia responde depois) ou `ninguem` (padrão: a
#   renovação segue como na E5, sem cotação);
# - `quem_envia`: `pessoa` (padrão: a proposta fica no card até alguém apertar Enviar) ou `sozinho`;
# - `quem_responde`: `lia` ou `equipe` (padrão);
# - `inbox_id`: a caixa do WhatsApp oficial por onde o "Algo mudou?" e a proposta saem. Nula: nada sai.
# As listas são validadas no model, sem CHECK: elas podem crescer (como `mensagens`).
#
# Chave: `inbox_id` → inboxes com SET NULL. Apagar a caixa não apaga as escolhas: a conta fica sem caixa e nada sai até
# alguém escolher outra. A exclusão da conta apaga a caixa e a linha de ajustes; com SET NULL a ordem não importa.
#
# Travas: cada ADD COLUMN pega ACCESS EXCLUSIVE em carteira_renovacao_configs só pelo instante. As três de texto têm
# padrão constante, que o Postgres guarda no catálogo sem reescrever a tabela (produção roda o 18); `inbox_id` é nula.
# O índice de `inbox_id` (serve ao SET NULL quando a caixa sai) entra CONCURRENTLY, fora de transação; o inválido de uma
# tentativa que caiu no meio sai antes de criar de novo. A chave entra NOT VALID (sem varrer linha) e é validada depois
# (a coluna nasce toda nula). Tudo com o lock_timeout curto do strong_migrations. Cada passo pode rodar de novo.
#
# Só aditiva: o código anterior não conhece as colunas, e as não nulas têm padrão.
#
# Rollback: o `down` tira a chave, o índice e as quatro colunas (nada mais depende delas). As escolhas gravadas se
# perdem: aceito, porque a chave da cotação nasce desligada em toda conta.
class AddCotacaoToCarteiraRenovacaoConfigs < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  TABELA = :carteira_renovacao_configs
  INDICE_DA_CAIXA = 'index_carteira_renovacao_configs_on_inbox_id'.freeze
  ESCOLHAS = { quem_cota: 'ninguem', quem_envia: 'pessoa', quem_responde: 'equipe' }.freeze

  def up
    ESCOLHAS.each { |coluna, padrao| add_column TABELA, coluna, :string, null: false, default: padrao, if_not_exists: true }
    add_column TABELA, :inbox_id, :bigint, if_not_exists: true
    criar_o_indice_da_caixa
    add_foreign_key TABELA, :inboxes, on_delete: :nullify, validate: false unless foreign_key_exists?(TABELA, :inboxes)
    validate_foreign_key TABELA, :inboxes
  end

  def down
    remove_foreign_key TABELA, :inboxes, if_exists: true
    remove_index TABELA, name: INDICE_DA_CAIXA, algorithm: :concurrently, if_exists: true
    remove_column TABELA, :inbox_id, if_exists: true
    ESCOLHAS.each_key { |coluna| remove_column TABELA, coluna, if_exists: true }
  end

  private

  def criar_o_indice_da_caixa
    remove_index TABELA, name: INDICE_DA_CAIXA, algorithm: :concurrently if index_exists?(TABELA, :inbox_id, name: INDICE_DA_CAIXA, valid: false)
    add_index TABELA, :inbox_id, name: INDICE_DA_CAIXA, algorithm: :concurrently, if_not_exists: true
  end
end
