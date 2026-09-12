# GUARDA: escrita no banco em TEMPO DE CARGA reprova a suíte deste nó.
#
# O corpo de um `describe`/`context` roda quando o RSpec CARREGA o arquivo — antes de existir
# exemplo, e portanto FORA da transação que `use_transactional_fixtures` abre por exemplo. A linha
# criada ali é COMMITADA e sobrevive ao processo inteiro, poluindo todos os exemplos de todos os
# outros arquivos do mesmo nó.
#
# Foi o defeito de `slack_uploads_controller_spec.rb` (corrigido no mesmo commit): um
# `ActiveStorage::Blob.create_and_upload!` no corpo do `context` deixava uma linha em
# `active_storage_blobs`, e as quatro asserções `expect(ActiveStorage::Blob.count).to eq(0)` de
# `entrega_de_arquivo_spec.rb` falhavam com `got: 1` — mas SÓ quando os dois arquivos caíam no
# mesmo nó. Como o CI fatia em round-robin sobre `find spec -name '*_spec.rb' | sort`
# (`.github/workflows/testes.yml`), UM arquivo novo em qualquer lugar da árvore remonta os blocos
# e o vermelho reaparece numa PR que não tem nada a ver com isso.
#
# QUEM DECIDE É O BANCO. A primeira versão desta guarda lia o TEXTO do SQL para separar escrita de
# leitura, e caiu três vezes em revisão, cada vez por um buraco diferente: string delimitada por
# cifrões (`SELECT $$ (INSERT INTO accounts) $$`) acusava quem só leu; comentário aninhado
# (`/* a /* b */ c */`) errava nos dois sentidos; `WITH a AS (SELECT 1) UPDATE accounts …` passava
# batido. Não é falta de capricho: expressão regular não analisa SQL, e cada remendo abre o
# próximo buraco. Então a decisão saiu do texto e foi para a contabilidade do próprio PostgreSQL —
# `pg_stat_user_tables`, medida no início da janela e no `before(:suite)`. Ela não interpreta nada:
# conta linha gravada, seja qual for a forma de escrever, inclusive por fora do ActiveRecord.
#
# O SUBSCRIBER DE `sql.active_record` CONTINUA, mas rebaixado a DIAGNÓSTICO: ele só anota
# `arquivo:linha` e o SQL bruto de tudo que sai de um `_spec.rb` durante a carga, sem classificar.
# Como não decide, não precisa acertar — e por isso a mensagem de erro chama a lista de SUSPEITOS,
# não de veredito. Se a medição acusar escrita e não houver suspeito (escrita por `raw_connection`,
# que não emite a notificação), a guarda reprova do mesmo jeito, dizendo a tabela que cresceu e que
# não localizou a origem. É justamente o caso que a versão por texto nunca pegaria.
#
# POR QUE `pg_stat_user_tables` E NÃO `pg_stat_database`: os contadores de `pg_stat_database`
# somam também o catálogo, então um DDL ou um autoanalyze durante a janela mexeria no número.
# `pg_stat_user_tables` conta só tabela de aplicação (é o `pg_stat_all_tables` sem `pg_catalog`,
# `information_schema` e toast) — que é exatamente o que polui os outros arquivos — e ainda diz
# QUAL tabela cresceu. VACUUM e ANALYZE não mexem em `n_tup_ins/upd/del`; medido: três leituras
# espaçadas em 3 s num banco ocioso deram o mesmo número.
#
# O ATRASO DA ESTATÍSTICA: desde o PostgreSQL 15 o backend acumula as contagens em memória local e
# só as descarrega na memória compartilhada a cada PGSTAT_MIN_INTERVAL. Medido: logo depois de um
# `INSERT` de 3 linhas o contador ainda marcava o valor velho; depois de `pg_stat_force_next_flush()`
# marcava exatamente +3. Por isso toda leitura aqui é precedida da descarga forçada. O CI roda
# `pgvector/pgvector:pg16` e o ambiente local é 16.13, então a função existe nos dois. Se ela não
# existir, ou o papel não puder chamá-la, a guarda NÃO adivinha: ela se ABSTÉM e avisa. Quem cobra
# a existência do sinal é o autoteste (`spec/guarda_de_escrita_na_carga_spec.rb`), que fica vermelho
# se o ambiente perder a função.
#
# A CONFERÊNCIA É DE SUÍTE, não um exemplo: um exemplo só roda no nó que sorteou o arquivo dele, e
# o vazamento pode estar em outro nó. Em `before(:suite)` ela roda em TODOS os nós, e reprova
# justamente o nó que carregou o arquivo culpado — que é o nó onde a poluição acontece. O
# `before(:suite)` também é o único lugar onde a medição fecha: a descarga da estatística só
# acontece no FIM de uma transação, e ali não há transação aberta (medido: dentro de um `BEGIN`
# o contador não se move nem com a descarga forçada).
#
# O QUE FICA DE FORA, sem disfarce:
#   - `rspec --dry-run` não roda hook nenhum, então lá a guarda é silenciosa.
#   - a guarda vê o que foi CARREGADO: arquivo fora da rodada não é conferido. No CI não é lacuna,
#     porque os oito nós juntos carregam todos.
#   - `n_tup_ins` conta linha gravada mesmo que a transação role atrás (medido). Na carga não há
#     transação aberta, então não muda o veredito; num `describe` que abrisse uma e desfizesse,
#     acusaria.
#   - a descarga forçada vale para o backend que a chama. A guarda a dispara em todas as conexões
#     vivas do pool do ActiveRecord; escrita feita por uma conexão fora do pool e ainda aberta só
#     aparece quando aquele backend fechar a transação dele (medido: 2,4 s depois, ainda invisível;
#     visível na desconexão).
module GuardaDeEscritaNaCarga
  # A MEDIÇÃO. `relid::regclass` dá o nome da tabela já qualificado quando precisa.
  MEDIDA = 'SELECT relid::regclass::text, n_tup_ins + n_tup_upd + n_tup_del FROM pg_stat_user_tables'.freeze
  DESCARGA = 'SELECT pg_stat_force_next_flush()'.freeze
  # `stats_fetch_consistency` vem como `cache`, que descarta o instantâneo no fim de cada transação;
  # como cada leitura daqui é a sua própria transação, um `pg_stat_clear_snapshot()` não muda nada
  # (medido: tirá-lo não derruba exemplo nenhum do autoteste). Ficou de fora em vez de virar enfeite.

  # O DIAGNÓSTICO. Só o que vem de um ARQUIVO DE SPEC: `rails_helper` e os helpers de `spec/support`
  # são carregados ANTES da janela abrir, então dentro dela quem consulta o banco a partir de um
  # frame de spec é candidato a ter escrito.
  ORIGEM = /_spec\.rb:\d+/
  TETO_DE_SUSPEITOS = 20

  class << self
    # Motivo pelo qual a medição não pôde ser feita, quando for o caso. `nil` = medição válida.
    attr_reader :motivo_da_abstencao

    def suspeitos
      @suspeitos ||= []
    end

    # Chamada no fim de `rails_helper`: depois de `maintain_test_schema!` (que escreve em
    # `ar_internal_metadata`) e antes de o RSpec carregar o primeiro arquivo de spec.
    def abrir!
      suspeitos.clear
      @motivo_da_abstencao = nil
      @linha_base = medir
      inscrever!
    end

    def inscrever!
      return if @assinatura

      @assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |_n, _i, _f, _id, dados|
        anotar(dados)
      end
    end

    def parar!
      ActiveSupport::Notifications.unsubscribe(@assinatura) if @assinatura
      @assinatura = nil
    end

    # Sem classificar SQL: anota tudo que saiu de um `_spec.rb`. Quem decide é a medição.
    def anotar(dados)
      return if suspeitos.size >= TETO_DE_SUSPEITOS

      origem = caller.find { |linha| linha.match?(ORIGEM) }
      return if origem.nil?

      endereco = origem.delete_prefix(Rails.root.to_s).delete_prefix('/')
      anotacao = "#{endereco}\n      #{dados[:sql].to_s.squish.truncate(140)}"
      suspeitos << anotacao unless suspeitos.include?(anotacao)
    end

    def conferir!
      parar!
      gravadas = @linha_base.nil? ? nil : crescimento(medir)
      return avisar_abstencao if gravadas.nil?
      return if gravadas.empty?

      raise mensagem(gravadas)
    end

    # Hash tabela => linhas gravadas desde que o PostgreSQL começou a contar, ou `nil` quando o
    # sinal não existe neste ambiente.
    def medir
      @motivo_da_abstencao = nil
      # Dentro de transação aberta a descarga não acontece e a leitura devolveria número velho —
      # falso negativo silencioso, que é o pior desfecho possível para uma guarda. Abster-se é
      # honesto; medir errado, não.
      return abster_se('medição pedida dentro de transação aberta') if ActiveRecord::Base.connection.transaction_open?

      descarregar_estatistica
      ActiveRecord::Base.connection.select_rows(MEDIDA).to_h.transform_values(&:to_i)
    rescue StandardError => e
      abster_se("#{e.class}: #{e.message.lines.first.to_s.strip}")
    end

    def abster_se(motivo)
      @motivo_da_abstencao = motivo
      nil
    end

    # A descarga vale para o backend que a chama, e o `execute` roda no backend daquela conexão.
    def descarregar_estatistica
      ActiveRecord::Base.connection_pool.connections.each do |conexao|
        conexao.execute(DESCARGA) if conexao.active?
      end
    end

    # Só crescimento: um `pg_stat_reset` no meio da janela daria diferença negativa, que não é
    # escrita nossa.
    def crescimento(agora)
      return nil if agora.nil?

      agora.filter_map do |tabela, linhas|
        escritas = linhas - @linha_base.fetch(tabela, 0)
        [tabela, escritas] if escritas.positive?
      end.to_h
    end

    def avisar_abstencao
      warn <<~AVISO
        [GuardaDeEscritaNaCarga] ABSTENÇÃO: o PostgreSQL não deu o sinal de escrita
        (#{motivo_da_abstencao}). A guarda NÃO conferiu a carga deste nó — ela não decide por
        aproximação. O autoteste `spec/guarda_de_escrita_na_carga_spec.rb` cobra a existência do
        sinal e fica vermelho quando o ambiente o perde.
      AVISO
    end

    def mensagem(gravadas)
      total = gravadas.values.sum
      <<~ERRO
        Escrita no banco durante a CARGA dos arquivos de spec — fora de `it`, `let` ou `before`.

        Quem acusa é o PostgreSQL: entre o fim de `rails_helper` e o `before(:suite)` deste nó,
        `pg_stat_user_tables` contou #{total} linha(s) gravada(s).

        #{gravadas.map { |tabela, linhas| "#{tabela}  +#{linhas}" }.join("\n    ")}

        O corpo de `describe`/`context` roda antes de existir exemplo, logo fora da transação de
        `use_transactional_fixtures`: a linha é COMMITADA e polui todos os exemplos deste nó.
        Mova a criação para `let` / `let!` / `before`.

        #{lista_de_suspeitos}
      ERRO
    end

    def lista_de_suspeitos
      if suspeitos.empty?
        <<~SEM.strip
          SUSPEITOS: nenhum. Nenhum SQL com origem em `_spec.rb` foi observado durante a carga —
          a escrita saiu por fora do ActiveRecord (`raw_connection`, por exemplo, que não emite
          `sql.active_record`) ou de um frame que o `caller` não atribui a um arquivo de spec.
          Procure pela tabela acima nos arquivos que este nó carregou.
        SEM
      else
        <<~COM.strip
          SUSPEITOS (SQL saído de um `_spec.rb` durante a carga). É lista de indício, não veredito:
          quem decidiu foi a medição acima, e o culpado pode não estar aqui.

              #{suspeitos.join("\n    ")}
        COM
      end
    end
  end
end
