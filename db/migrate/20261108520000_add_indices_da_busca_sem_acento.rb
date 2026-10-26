# #2211 — a busca da lista de conversas acha "João" digitando "joao", no nome do contato, no título do card, no texto da
# mensagem e no áudio transcrito. Quatro índices trigram (GIN) sobre
#   lower(translate(normalize(coluna, NFD), <acentos combinantes>, ''))
# — a mesma expressão de SearchService::SemAcento, que a consulta usa. Só funções que já vêm no Postgres (normalize
# existe desde o 13 e é IMMUTABLE; banco UTF8), sem extensão e sem função nossa no banco: o db/schema.rb guarda a
# expressão e carrega num banco novo.
#
# A lista de acentos está escrita aqui, congelada: migration não muda depois de rodar. O spec sem_acento_spec confere
# que o db/schema.rb, o banco e a constante do código continuam iguais.
#
# Cada índice:
# - já existe e é válido: fica como está;
# - existe e é inválido (rodada interrompida): é apagado, concurrently;
# - é criado concurrently, sem IF NOT EXISTS, e conferido depois: se não ficou válido, a migration para com erro.
# CREATE INDEX CONCURRENTLY não trava leitura nem escrita, mas espera quem está escrevendo na tabela. Com o lock_timeout
# do StrongMigrations (5 s) a espera estourava, o índice ficava inválido, e a nova tentativa da gem com IF NOT EXISTS o
# dava por pronto. Por isso, só durante cada CREATE/DROP INDEX CONCURRENTLY, o lock_timeout sobe para 15 min e o
# statement_timeout fica zerado; os dois voltam no ensure.
class AddIndicesDaBuscaSemAcento < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  # Os acentos que a NFD gera para as letras de U+00C0 a U+017F, na ordem canônica do Unicode.
  ACENTOS_COMBINANTES = [
    '̧', # U+0327 cedilha: ç
    '̨', # U+0328 ogonek: ą
    '̀', # U+0300 acento grave: à
    '́', # U+0301 acento agudo: á
    '̂', # U+0302 circunflexo: â
    '̃', # U+0303 til: ã
    '̄', # U+0304 mácron: ā
    '̆', # U+0306 breve: ă
    '̇', # U+0307 ponto em cima: ċ, İ
    '̈', # U+0308 trema: ü
    '̊', # U+030A anel: å
    '̋', # U+030B agudo duplo: ő
    '̌'  # U+030C caron: č
  ].join.freeze

  INDICES = [
    [:contacts, 'name', 'idx_contacts_nome_sem_acento_trgm'],
    [:crm_cards, 'title', 'idx_crm_cards_titulo_sem_acento_trgm'],
    [:messages, 'content', 'idx_messages_conteudo_sem_acento_trgm'],
    [:attachments, "(meta ->> 'transcribed_text')", 'idx_attachments_transcricao_sem_acento_trgm']
  ].freeze

  def up
    INDICES.each do |tabela, coluna, nome|
      next if valido?(nome) == true

      com_espera_longa do
        # Índice inválido também pode ser o CREATE CONCURRENTLY de outro processo que ainda está rodando (órfão de um
        # deploy interrompido). Quem impede apagar o índice debaixo dele hoje é a trava de migration do Rails (advisory
        # lock da sessão): enquanto a sessão daquele processo estiver viva, esta migration nem começa.
        remove_index tabela, name: nome, algorithm: :concurrently if valido?(nome) == false
        add_index tabela, "lower(translate(normalize(#{coluna}, NFD), '#{ACENTOS_COMBINANTES}', '')) gin_trgm_ops",
                  using: :gin, name: nome, algorithm: :concurrently
      end
      raise "#2211: o índice #{nome} foi criado, mas ficou inválido" unless valido?(nome) == true
    end
  end

  def down
    INDICES.reverse_each do |tabela, _coluna, nome|
      com_espera_longa { remove_index tabela, name: nome, algorithm: :concurrently, if_exists: true }
    end
  end

  private

  # lock_timeout finito e alto, não zero: espera sem fim prenderia o deploy. Se estourar, o CREATE falha alto: sem IF NOT
  # EXISTS, a nova tentativa do StrongMigrations bate no índice inválido que sobrou e também falha, e a rodada seguinte
  # desta migration apaga o inválido e refaz.
  def com_espera_longa
    anteriores = { 'lock_timeout' => select_value('SHOW lock_timeout'), 'statement_timeout' => select_value('SHOW statement_timeout') }
    safety_assured { execute "SET lock_timeout = '15min'; SET statement_timeout = 0" }
    yield
  ensure
    anteriores&.each { |nome, valor| safety_assured { execute "SET #{nome} = #{connection.quote(valor)}" } }
  end

  # true = existe e é válido; false = existe e é inválido; nil = não existe.
  def valido?(nome)
    select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{connection.quote(nome)}")
  end
end
