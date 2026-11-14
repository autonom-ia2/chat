# E6 (#2899), parte 0: onde fica uma leitura de PDFs antes do Conferir, e o que a apólice guarda do PDF. Nada lê nem
# grava aqui ainda (o leitor, o anexar e o trazer por PDFs vêm nos PRs seguintes, atrás de Carteira::Acesso).
# - `carteira_leituras`: um lote de leitura da conta. É o que o Conferir mostra, o que o histórico lista e o que o
#   Desfazer desfaz. `origem` é `pdf` (E6) ou `conector` (a busca da E7 usa a mesma tabela). `totais` guarda só
#   contagens. O estado não tem CHECK: cresce com quem grava e é validado no model.
# - `carteira_leitura_itens`: um arquivo (ou um registro do conector) do lote. `campos` é o que foi lido, em forma
#   canônica, e `duvidas`, os nomes dos campos sem certeza. Guarda dado de cliente em jsonb e o PDF (Active Storage):
#   os itens são apagados pelo app dias depois de a leitura ser confirmada ou abandonada (Carteira::LeituraItem).
#   Tem `account_id` próprio, o da leitura: a linha guarda dado de cliente, e a conta dela não pode depender de um JOIN.
# - `carteira_apolices` ganha sete colunas: `leitura_id` (o lote que criou a apólice), `duvidas` (campos lidos sem
#   certeza), `de_fora`, `corretora_de_fora` e `lembrete_aceito_em` (o seguro de outra corretora que vira lembrete),
#   `palavras_texto` e `palavras_enviadas_em` (o seguro em palavras simples).
#
# Chaves:
# - leituras.account: sem cascata, como as outras tabelas do fork; Autonomia::ExclusaoDaConta apaga antes da conta;
# - leituras.user: SET NULL. Apagar a pessoa não apaga o lote;
# - itens.account: sem cascata, como a da leitura; a exclusão da conta tira os itens (com o PDF) antes das leituras;
# - itens.leitura: em cascata, o item não existe sem o lote. A cascata é só a proteção do banco contra linha órfã: ela
#   NÃO apaga o PDF do item. Por isso o app nunca apaga leitura com `delete` nem `delete_all`, só com `destroy`, que
#   passa por cada item e tira o arquivo (Carteira::Leitura). A limpeza dos itens vencidos (E6.2) usa `destroy` em lote
#   pequeno, e a exclusão da conta tira os itens e os anexos deles antes das leituras;
# - itens.contact e itens.apolice: SET NULL. Apagar a pessoa ou o seguro não apaga o que foi lido;
# - apolices.leitura: SET NULL. Apagar o lote não apaga seguro.
#
# Índices: [account_id, created_at] serve ao histórico da conta e à chave dela (começa por account_id). O de
# `account_id` dos itens serve à chave da conta e à exclusão dela. O único [leitura_id, posicao] é a ordem dos itens e
# serve à cascata. Os parciais em `user_id`, `contact_id` e `apolice_id` servem ao SET NULL de cada chave. O parcial em
# `carteira_apolices.leitura_id` serve ao Desfazer e ao SET NULL; entra CONCURRENTLY, fora de transação, e não trava a
# escrita na carteira. Um CREATE INDEX CONCURRENTLY que cai no meio deixa o índice INVALID, e o `if_not_exists` o
# aceitaria como pronto: por isso o inválido é tirado antes de criar de novo. Os das tabelas novas nascem com elas,
# vazias.
#
# Travas: cada CREATE TABLE pega SHARE ROW EXCLUSIVE nas tabelas que as chaves apontam (accounts e users no primeiro;
# accounts, carteira_leituras, contacts e carteira_apolices no segundo) pelo instante do comando, sem varrer linha. Cada ADD
# COLUMN pega ACCESS EXCLUSIVE em carteira_apolices só pelo instante: as duas colunas com padrão (`duvidas` e `de_fora`)
# têm padrão constante, que o Postgres guarda no catálogo sem reescrever a tabela (produção roda o 18); as outras são
# nulas. A chave de `leitura_id` entra NOT VALID e é validada depois (SHARE UPDATE EXCLUSIVE: leitura e escrita seguem;
# a coluna nasce toda nula). Tudo com o lock_timeout curto do strong_migrations (5 s, 3 tentativas). Cada passo pode
# rodar de novo sem erro se o deploy cair no meio.
#
# A migration roda fora de transação por causa do índice CONCURRENTLY, que é o único comando que precisa disso e é em
# tabela que já existe. Cada tabela NOVA é criada dentro de uma transação própria (tabela, chaves e índices dela): sem
# isso, uma queda entre o CREATE TABLE e os índices deixaria no banco uma tabela sem os índices dela (inclusive o
# único) até a migration rodar de novo. As chaves vão dentro do próprio CREATE TABLE; os índices são comandos à parte.
# Dentro de transação o strong_migrations não repete o comando quando a trava estoura (repetir um comando numa
# transação que já falhou não funciona), então a repetição da transação inteira é feita aqui, com os mesmos números
# dele.
#
# Só aditiva: o código anterior não conhece as tabelas nem as colunas,
# e nenhuma coluna nova é obrigatória para ele (as não nulas têm padrão).
#
# Rollback: o `down` tira a chave, o índice, as sete colunas e as duas tabelas (nada mais depende deles). Antes de
# derrubar a tabela dos itens, tira os PDFs deles: DROP TABLE não apaga arquivo, e o anexo ficaria apontando para nada.
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
    inteira { criar_leituras }
    inteira { criar_itens }
    COLUNAS.each { |coluna, tipo, opcoes| add_column :carteira_apolices, coluna, tipo, **opcoes, if_not_exists: true }
    criar_o_indice_da_leitura
    ligar_a_leitura
  end

  def down
    remove_foreign_key :carteira_apolices, :carteira_leituras, column: :leitura_id, if_exists: true
    remove_index :carteira_apolices, name: INDICE_DA_LEITURA, algorithm: :concurrently, if_exists: true
    COLUNAS.each { |coluna, _tipo, _opcoes| remove_column :carteira_apolices, coluna, if_exists: true }
    apagar_os_pdfs_dos_itens
    drop_table :carteira_leitura_itens, if_exists: true
    drop_table :carteira_leituras, if_exists: true
  end

  private

  # A tabela nova nasce inteira ou não nasce.
  def inteira(&)
    tentativas = 0
    begin
      connection.transaction(&)
    rescue ActiveRecord::LockWaitTimeout
      tentativas += 1
      raise if tentativas > StrongMigrations.lock_timeout_retries

      sleep(StrongMigrations.lock_timeout_retry_delay)
      retry
    end
  end

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
      t.references :account, null: false, foreign_key: true
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

  def criar_o_indice_da_leitura
    if index_exists?(:carteira_apolices, :leitura_id, name: INDICE_DA_LEITURA, valid: false)
      remove_index :carteira_apolices, name: INDICE_DA_LEITURA, algorithm: :concurrently
    end
    add_index :carteira_apolices, :leitura_id, where: 'leitura_id IS NOT NULL', name: INDICE_DA_LEITURA,
                                               algorithm: :concurrently, if_not_exists: true
  end

  # O mesmo caminho de Autonomia::ExclusaoDaConta#apagar_anexos: tira os anexos e manda apagar o arquivo que nenhum
  # outro anexo usa. Pelo nome da classe, sem carregar o model (que pode não existir mais quando o `down` rodar).
  def apagar_os_pdfs_dos_itens
    anexos = ActiveStorage::Attachment.where(record_type: 'Carteira::LeituraItem')
    blob_ids = anexos.pluck(:blob_id)
    anexos.delete_all
    ActiveStorage::Blob.where(id: blob_ids).where.missing(:attachments).find_each(&:purge_later)
  end

  # NOT VALID e depois VALIDATE: a chave nova não varre a tabela com a trava que barra a escrita.
  def ligar_a_leitura
    unless foreign_key_exists?(:carteira_apolices, :carteira_leituras, column: :leitura_id)
      add_foreign_key :carteira_apolices, :carteira_leituras, column: :leitura_id, on_delete: :nullify, validate: false
    end
    validate_foreign_key :carteira_apolices, :carteira_leituras, column: :leitura_id
  end
end
