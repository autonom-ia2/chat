# E6 (#2899), parte 0: onde fica uma leitura de PDFs antes do Conferir, e o que a apólice guarda do PDF. Nada lê nem
# grava aqui ainda (o leitor, o anexar e o trazer por PDFs vêm nos PRs seguintes, atrás de Carteira::Acesso).
# - `carteira_leituras`: um lote de leitura da conta. É o que o Conferir mostra, o que o histórico lista e o que o
#   Desfazer desfaz. `origem` é `pdf` (E6) ou `conector` (a busca da E7 usa a mesma tabela). `totais` guarda só
#   contagens. O estado não tem CHECK: cresce com quem grava e é validado no model.
# - `carteira_leitura_itens`: um arquivo (ou um registro do conector) do lote. `campos` é o que foi lido, em forma
#   canônica, e `duvidas`, os nomes dos campos sem certeza. Guarda dado de cliente em jsonb e o PDF (Active Storage):
#   os itens são apagados pelo app dias depois de a leitura ser confirmada ou abandonada (Carteira::LeituraItem).
#   Sem account_id: o item é da leitura.
# - `carteira_apolices` ganha sete colunas: `leitura_id` (o lote que criou a apólice), `duvidas` (campos lidos sem
#   certeza), `de_fora`, `corretora_de_fora` e `lembrete_aceito_em` (o seguro de outra corretora que vira lembrete),
#   `palavras_texto` e `palavras_enviadas_em` (o seguro em palavras simples).
#
# Chaves:
# - leituras.account: sem cascata, como as outras tabelas do fork; Autonomia::ExclusaoDaConta apaga antes da conta;
# - leituras.user: SET NULL. Apagar a pessoa não apaga o lote;
# - itens.leitura: em cascata, o item não existe sem o lote. Quem apaga item com PDF é o app (a cascata do banco não
#   apaga arquivo), e a exclusão da conta tira os itens antes das leituras;
# - itens.contact e itens.apolice: SET NULL. Apagar a pessoa ou o seguro não apaga o que foi lido;
# - apolices.leitura: SET NULL. Apagar o lote não apaga seguro.
#
# Índices: [account_id, created_at] serve ao histórico da conta e à chave dela (começa por account_id). O único
# [leitura_id, posicao] é a ordem dos itens e serve à cascata. Os parciais em `user_id`, `contact_id` e `apolice_id`
# servem ao SET NULL de cada chave. O parcial em `carteira_apolices.leitura_id` serve ao Desfazer e ao SET NULL; entra
# CONCURRENTLY, fora de transação, e não trava a escrita na carteira. Os das tabelas novas nascem com elas, vazias.
#
# Travas: cada CREATE TABLE pega SHARE ROW EXCLUSIVE nas tabelas que as chaves apontam (accounts e users no primeiro;
# carteira_leituras, contacts e carteira_apolices no segundo) pelo instante do comando, sem varrer linha. Cada ADD
# COLUMN pega ACCESS EXCLUSIVE em carteira_apolices só pelo instante: as duas colunas com padrão (`duvidas` e `de_fora`)
# têm padrão constante, que o Postgres guarda no catálogo sem reescrever a tabela (produção roda o 18); as outras são
# nulas. A chave de `leitura_id` entra NOT VALID e é validada depois (SHARE UPDATE EXCLUSIVE: leitura e escrita seguem;
# a coluna nasce toda nula). Tudo com o lock_timeout curto do strong_migrations (5 s, 3 tentativas). Cada passo pode
# rodar de novo sem erro se o deploy cair no meio. Só aditiva: o código anterior não conhece as tabelas nem as colunas,
# e nenhuma coluna nova é obrigatória para ele (as não nulas têm padrão).
#
# Rollback: o `down` tira a chave, o índice, as sete colunas e as duas tabelas (nada mais depende deles).
class CreateCarteiraLeituras < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  ORIGENS = "origem::text = ANY ('{pdf,conector}'::text[])".freeze
  INDICE_DA_LEITURA = 'idx_carteira_apolices_leitura'.freeze
  # [coluna, tipo, opções]
  COLUNAS = [
    [:leitura_id, :bigint, {}], [:duvidas, :jsonb, { null: false, default: [] }], [:de_fora, :boolean, { null: false, default: false }],
    [:corretora_de_fora, :string, {}], [:lembrete_aceito_em, :datetime, {}], [:palavras_texto, :text, {}],
    [:palavras_enviadas_em, :datetime, {}]
  ].freeze

  def up
    criar_leituras
    criar_itens
    COLUNAS.each { |coluna, tipo, opcoes| add_column :carteira_apolices, coluna, tipo, **opcoes, if_not_exists: true }
    add_index :carteira_apolices, :leitura_id, where: 'leitura_id IS NOT NULL', name: INDICE_DA_LEITURA,
                                               algorithm: :concurrently, if_not_exists: true
    ligar_a_leitura
  end

  def down
    remove_foreign_key :carteira_apolices, :carteira_leituras, column: :leitura_id, if_exists: true
    remove_index :carteira_apolices, name: INDICE_DA_LEITURA, algorithm: :concurrently, if_exists: true
    COLUNAS.each { |coluna, _tipo, _opcoes| remove_column :carteira_apolices, coluna, if_exists: true }
    drop_table :carteira_leitura_itens, if_exists: true
    drop_table :carteira_leituras, if_exists: true
  end

  private

  def criar_leituras
    create_table :carteira_leituras, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :user, foreign_key: { on_delete: :nullify }, index: { where: 'user_id IS NOT NULL' }
      t.string :origem, null: false
      t.string :estado, null: false, default: 'lendo'
      t.jsonb :totais, null: false, default: {}
      t.datetime :confirmada_em
      t.datetime :desfeita_em
      t.timestamps
      t.index %i[account_id created_at]
      t.check_constraint ORIGENS, name: 'carteira_leituras_origem'
    end
  end

  def criar_itens
    create_table :carteira_leitura_itens, if_not_exists: true do |t|
      t.references :leitura, null: false, foreign_key: { to_table: :carteira_leituras, on_delete: :cascade }, index: false
      t.integer :posicao, null: false
      t.string :estado, null: false, default: 'lendo'
      t.jsonb :campos, null: false, default: {}
      t.jsonb :duvidas, null: false, default: []
      t.references :contact, foreign_key: { on_delete: :nullify }, index: { where: 'contact_id IS NOT NULL' }
      t.references :apolice, foreign_key: { to_table: :carteira_apolices, on_delete: :nullify }, index: { where: 'apolice_id IS NOT NULL' }
      t.timestamps
      t.index %i[leitura_id posicao], unique: true
    end
  end

  # NOT VALID e depois VALIDATE: a chave nova não varre a tabela com a trava que barra a escrita.
  def ligar_a_leitura
    unless foreign_key_exists?(:carteira_apolices, :carteira_leituras, column: :leitura_id)
      add_foreign_key :carteira_apolices, :carteira_leituras, column: :leitura_id, on_delete: :nullify, validate: false
    end
    validate_foreign_key :carteira_apolices, :carteira_leituras, column: :leitura_id
  end
end
