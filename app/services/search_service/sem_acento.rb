# #2211 — "joao" acha "João". A expressão tira o acento em duas etapas, só com funções que já vêm no Postgres (sem função
# nossa no banco, sem extensão): normalize(..., NFD) separa cada letra acentuada em letra + acento combinante, e
# translate apaga os acentos combinantes desta lista. É a mesma expressão dos índices trigram da migration 20261108520000,
# que guarda uma cópia literal (migration não muda depois de rodar); o spec sem_acento_spec confere o db/schema.rb, o
# banco e o Ruby.
#
# Por que não uma tabela "Á → A": o translate compara cada letra do texto com a tabela inteira. Com as 161 letras do
# Latin, isso custava ~140 µs por mensagem e a busca de um termo comum passava de 1,5 s na carga da hub; com os 13
# acentos abaixo, ~10 µs.
#
# Mudar a lista exige migration nova que recrie os índices: a consulta só usa o índice quando a expressão é idêntica.
module SearchService::SemAcento
  # Os acentos combinantes que a decomposição NFD gera para todas as letras do Latin-1 Supplement e do Latin Extended-A
  # (U+00C0 a U+017F, onde estão as letras do português, do espanhol e das outras línguas latinas). O spec deriva a
  # lista de novo dessas letras e compara. Cada acento está escrito como o próprio caractere, entre aspas simples (sozinho
  # ele aparece em cima da aspa); o comentário diz qual é. A ordem é a canônica do Unicode (classe 202, cedilha e ogonek,
  # antes da 230): normalizar o arquivo não muda nada. A migration 20261108520000 tem a mesma lista, congelada.
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

  module_function

  # A expressão do índice, em SQL. `coluna` é SQL escrito no código, nunca texto do usuário. A lista entra como texto
  # literal; nenhum acento combinante é aspa.
  def sql(coluna)
    "lower(translate(normalize(#{coluna}, NFD), '#{ACENTOS_COMBINANTES}', ''))"
  end

  # Cada palavra precisa aparecer na expressão, em qualquer ordem e sem diferença de acento. A palavra passa pela mesma
  # expressão no banco (bind), não pelo Ruby: o resultado não depende da collation. O Postgres resolve a expressão da
  # palavra antes de planejar, e o índice trigram continua valendo. Devolve [sql, *valores].
  def todas_as_palavras(expressao, palavras)
    condicoes = palavras.map { "#{sql(expressao)} LIKE '%' || #{sql('?')} || '%'" }.join(' AND ')
    [condicoes, *palavras.map { |palavra| ActiveRecord::Base.sanitize_sql_like(palavra) }]
  end

  # O mesmo, no Ruby (só para conferir nos specs que o banco e o Ruby concordam).
  def texto(valor)
    valor.to_s.unicode_normalize(:nfd).delete(ACENTOS_COMBINANTES).downcase
  end
end
