# E5 (#2898), parte 0: o que a renovação no funil guarda. Só o que é da E5; nada lê nem grava aqui ainda (a API, a rotina
# e o ouvinte do desfecho vêm no PR seguinte, atrás de Carteira::Acesso).
# - `carteira_renovacao_configs`: onde ficam as renovações de cada conta (uma linha por conta): o funil e a etapa em que
#   o card nasce, quantos dias antes do fim e se as mensagens saem. Funil e etapa nulos = a conta ainda não escolheu, ou
#   o funil foi apagado; nesse caso nada vira card.
# - `carteira_apolices` ganha sete colunas, todas nulas e sem padrão (ADD COLUMN não reescreve a tabela):
#   `crm_card_id` (o card de renovação desta apólice), `renovacao_card_removido_em` (quem apagou o card de propósito não
#   o vê voltar nesta vigência), `apolice_anterior_id` (a apólice que esta renovou), `renovado_em`, `nao_renovou_em`,
#   `motivo_nao_renovou` e `motivo_escrito`. A lista de motivos é validada no model, sem CHECK: ela pode crescer.
#
# Chaves:
# - configs.account: sem cascata, como as outras tabelas do fork; Autonomia::ExclusaoDaConta apaga a linha antes do
#   DELETE da conta;
# - configs.pipeline, configs.stage e configs.user: SET NULL. Apagar o funil, a etapa ou a pessoa não apaga a escolha:
#   a conta volta a "ainda não escolheu";
# - apolices.crm_card: SET NULL. Apagar o card não apaga o seguro;
# - apolices.apolice_anterior: SET NULL, para a própria tabela. Apagar a apólice antiga não apaga a que a renovou.
#
# Índices: o único parcial em `crm_card_id` é "um card por apólice" e a idempotência da rotina (duas apólices nunca
# apontam para o mesmo card); também serve ao SET NULL da chave quando o card é apagado. O parcial em
# `apolice_anterior_id` serve ao SET NULL da própria tabela. Os dois entram CONCURRENTLY, fora de transação: não travam
# a escrita na carteira. Os da tabela nova nascem com ela, vazia.
#
# Travas: o CREATE TABLE pega SHARE ROW EXCLUSIVE em accounts, crm_pipelines, crm_pipeline_stages e users pelo instante
# do comando. Cada ADD COLUMN pega ACCESS EXCLUSIVE em carteira_apolices só pelo instante (coluna nula, sem padrão). As
# duas chaves entram NOT VALID (SHARE ROW EXCLUSIVE em carteira_apolices e em crm_cards, sem varrer linha) e são
# validadas depois (SHARE UPDATE EXCLUSIVE: leitura e escrita seguem; as colunas nascem todas nulas). Tudo com o
# lock_timeout curto do strong_migrations (5 s, 3 tentativas). Cada passo pode rodar de novo sem erro se o deploy cair
# no meio. Só aditiva: o código anterior não conhece a tabela nem as colunas, e nenhuma é obrigatória.
#
# Rollback: o `down` tira as duas chaves, os dois índices, as sete colunas e a tabela (nada mais depende deles).
class AddRenovacaoToCarteira < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  DIAS = 'dias_antes >= 1'.freeze
  INDICE_DO_CARD = 'idx_carteira_apolices_crm_card'.freeze
  INDICE_DA_ANTERIOR = 'idx_carteira_apolices_apolice_anterior'.freeze
  COLUNAS = {
    crm_card_id: :bigint, renovacao_card_removido_em: :datetime, apolice_anterior_id: :bigint, renovado_em: :datetime,
    nao_renovou_em: :datetime, motivo_nao_renovou: :string, motivo_escrito: :string
  }.freeze
  # [coluna, tabela para onde aponta]
  CHAVES = { crm_card_id: :crm_cards, apolice_anterior_id: :carteira_apolices }.freeze

  def up
    criar_ajustes
    COLUNAS.each { |coluna, tipo| add_column :carteira_apolices, coluna, tipo, if_not_exists: true }
    add_index :carteira_apolices, :crm_card_id, unique: true, where: 'crm_card_id IS NOT NULL', name: INDICE_DO_CARD,
                                                algorithm: :concurrently, if_not_exists: true
    add_index :carteira_apolices, :apolice_anterior_id, where: 'apolice_anterior_id IS NOT NULL', name: INDICE_DA_ANTERIOR,
                                                        algorithm: :concurrently, if_not_exists: true
    CHAVES.each { |coluna, tabela| ligar(coluna, tabela) }
  end

  def down
    CHAVES.each { |coluna, tabela| remove_foreign_key :carteira_apolices, tabela, column: coluna, if_exists: true }
    remove_index :carteira_apolices, name: INDICE_DA_ANTERIOR, algorithm: :concurrently, if_exists: true
    remove_index :carteira_apolices, name: INDICE_DO_CARD, algorithm: :concurrently, if_exists: true
    COLUNAS.each_key { |coluna| remove_column :carteira_apolices, coluna, if_exists: true }
    drop_table :carteira_renovacao_configs, if_exists: true
  end

  private

  def criar_ajustes
    create_table :carteira_renovacao_configs, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.references :pipeline, foreign_key: { to_table: :crm_pipelines, on_delete: :nullify }
      t.references :stage, foreign_key: { to_table: :crm_pipeline_stages, on_delete: :nullify }
      t.integer :dias_antes, null: false, default: 60
      t.string :mensagens, null: false, default: 'mandar'
      t.references :user, foreign_key: { on_delete: :nullify }
      t.timestamps
      t.check_constraint DIAS, name: 'carteira_renovacao_configs_dias'
    end
  end

  # NOT VALID e depois VALIDATE: a chave nova não varre a tabela com a trava que barra a escrita.
  def ligar(coluna, tabela)
    unless foreign_key_exists?(:carteira_apolices, tabela, column: coluna)
      add_foreign_key :carteira_apolices, tabela, column: coluna, on_delete: :nullify, validate: false
    end
    validate_foreign_key :carteira_apolices, tabela, column: coluna
  end
end
