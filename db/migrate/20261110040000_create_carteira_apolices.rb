# E4 (#2897), fatia 1: a carteira de seguros da corretora. Duas tabelas novas; nada lê nem grava nelas ainda (a API e a
# flag `carteira_seguros` vêm nas fatias seguintes).
# - `carteira_apolices`: um seguro de uma pessoa da ficha. `seguradora_chave` e `numero_chave` são a forma de comparação
#   de `seguradora` e `numero`, calculada por quem grava. `numero` aceita nulo para o seguro que chega sem número.
# - `carteira_apolice_eventos`: a história de cada apólice (chegou pela planilha, foi corrigida, cancelada). Sem
#   account_id: o evento é da apólice e sai com ela.
#
# Chaves:
# - account: sem cascata, como as outras tabelas do fork; a exclusão da conta (Autonomia::ExclusaoDaConta) apaga as
#   apólices antes do DELETE da conta;
# - contact: SEM cascata. A apólice tem PDF (Active Storage) e a cascata do banco apagaria a linha e deixaria o arquivo.
#   Quem apaga a apólice é o app; na exclusão da conta ela sai antes do pré-apagar dos contatos;
# - company e campaign_import: SET NULL. Apagar a empresa ou a importação não apaga seguro; a apólice continua na pessoa;
# - eventos.apolice: em cascata, a história não existe sem a apólice. eventos.user e eventos.campaign_import: SET NULL.
#
# Índices: `contact_id` inteiro (não parcial) serve à ficha e ao gatilho da chave quando o contato é apagado. O único
# [account_id, seguradora_chave, numero_chave, fim_vigencia] é "a mesma apólice": por conta, e com o fim da vigência
# para a renovação que mantém o número caber ao lado da anterior. Só vale com número. [account_id, fim_vigencia] também
# atende a chave da conta (começa por ela), então account_id não ganha índice próprio. eventos.user_id fica sem índice:
# nenhuma tela procura por ele; apagar um usuário (raro) varre a história uma vez para anular a coluna.
#
# Tipo e origem são texto com CHECK, o padrão do fork (não enum do Rails nem do Postgres). O tipo do evento não tem
# CHECK: cresce a cada etapa e é validado no model.
#
# Travas: só CREATE TABLE. Cada um pega SHARE ROW EXCLUSIVE nas tabelas que as chaves apontam (accounts, contacts,
# companies e campaign_imports no primeiro; campaign_imports e users no segundo): bloqueia a escrita nelas pelo instante
# do comando, sem varrer linha, porque a tabela nova nasce vazia. Sem transação em volta, a trava de um comando cai antes
# do seguinte. Todos rodam com o lock_timeout curto do strong_migrations (5 s, 3 tentativas,
# config/initializers/strong_migrations.rb): se uma transação longa segura uma dessas tabelas, a migration desiste em
# vez de enfileirar as escritas atrás dela, e o deploy falha antes do tráfego. Os índices são das tabelas novas, vazias.
# Cada passo pode rodar de novo sem erro se o deploy cair no meio. O down remove as duas.
class CreateCarteiraApolices < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  TIPOS = "tipo::text = ANY ('{auto,residencial,vida,empresarial,outro}'::text[])".freeze
  ORIGENS = "origem::text = ANY ('{planilha,manual,pdf,conector}'::text[])".freeze
  VIGENCIA = 'inicio_vigencia IS NULL OR fim_vigencia >= inicio_vigencia'.freeze
  VALOR = 'valor_centavos IS NULL OR valor_centavos >= 0'.freeze

  def up
    criar_apolices
    criar_eventos
  end

  def down
    drop_table :carteira_apolice_eventos, if_exists: true
    drop_table :carteira_apolices, if_exists: true
  end

  private

  def criar_apolices
    create_table :carteira_apolices, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :contact, null: false, foreign_key: true
      t.references :company, foreign_key: { on_delete: :nullify }, index: { where: 'company_id IS NOT NULL' }
      dados_da_apolice(t)
      t.references :campaign_import, foreign_key: { on_delete: :nullify }, index: { where: 'campaign_import_id IS NOT NULL' }
      t.jsonb :corrigido_a_mao, null: false, default: []
      t.timestamps
      indices_e_regras_da_apolice(t)
    end
  end

  def dados_da_apolice(tabela)
    tabela.string :tipo, null: false
    tabela.string :ramo_original
    tabela.string :seguradora, null: false
    tabela.string :seguradora_chave, null: false
    tabela.string :numero
    tabela.string :numero_chave
    tabela.date :inicio_vigencia
    tabela.date :fim_vigencia, null: false
    tabela.bigint :valor_centavos
    tabela.string :bem
    tabela.datetime :cancelado_em
    tabela.string :origem, null: false
  end

  def indices_e_regras_da_apolice(tabela)
    tabela.index %i[account_id fim_vigencia]
    tabela.index %i[account_id seguradora_chave numero_chave fim_vigencia], unique: true, where: 'numero_chave IS NOT NULL',
                                                                            name: 'idx_carteira_apolices_seguradora_numero_vigencia'
    tabela.check_constraint TIPOS, name: 'carteira_apolices_tipo'
    tabela.check_constraint ORIGENS, name: 'carteira_apolices_origem'
    tabela.check_constraint VIGENCIA, name: 'carteira_apolices_vigencia'
    tabela.check_constraint VALOR, name: 'carteira_apolices_valor'
  end

  def criar_eventos
    create_table :carteira_apolice_eventos, if_not_exists: true do |t|
      t.references :apolice, null: false, foreign_key: { to_table: :carteira_apolices, on_delete: :cascade }, index: false
      t.string :tipo, null: false
      t.datetime :quando, null: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.jsonb :valores, null: false, default: {}
      t.jsonb :mudancas
      t.references :campaign_import, foreign_key: { on_delete: :nullify }, index: { where: 'campaign_import_id IS NOT NULL' }
      t.datetime :created_at, null: false
      t.index %i[apolice_id quando], order: { quando: :desc }
    end
  end
end
