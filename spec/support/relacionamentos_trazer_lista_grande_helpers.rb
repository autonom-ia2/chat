# #2896 (fatia 3): uma lista trazida grande, montada direto no banco (insert_all), para medir o que o "Desfazer" lê.
# Passar pela leitura e pela gravação de verdade levaria minutos; aqui só importa o que elas deixam gravado: as pessoas,
# as linhas da importação e os campos anotados. Todos os dados são inventados.
#
# Quem usa inclui o módulo no próprio spec (`include ListaTrazidaGrandeHelpers`): ele não entra em todos os specs.
module ListaTrazidaGrandeHelpers
  LOTE = 5_000
  CLIENTE_DESDE = Time.utc(2026, 1, 15, 12)
  CIDADE = 'Campinas'.freeze
  # De cada tantas pessoas que a lista criou, uma recusou mensagens: é a que fica.
  UMA_RECUSA_A_CADA = 20
  Medida = Struct.new(:resultado, :consultas, :segundos, :por_tabela, keyword_init: true)

  # A lista já gravada, ainda sem linha nenhuma.
  def lista_trazida_vazia(conta, quem)
    conta.campaign_imports.create!(user: quem, status: :completed, mode: 'single_label',
                                   options: { 'flow' => CampaignImport::CONTACTS_FLOW, 'trazer' => {} })
  end

  # `quantas` pessoas que a lista criou, uma linha cada, com o resumo de cada uma anotado como a gravação anota (nenhuma
  # foi editada depois). Devolve quantas recusaram mensagens.
  def por_pessoas_criadas(importacao, quantas)
    em_lotes(importacao, quantas) do |numeros|
      pessoas = numeros.map { |numero| pessoa_criada(importacao.account_id, numero) }
      ids = diag_tempo('criadas', 'pessoas') { inserir(Contact, pessoas) }
      linhas = diag_tempo('criadas', 'linhas') { inserir_linhas(importacao, numeros, ids, ja_existia: false) }
      diag_tempo('criadas', 'campos', vigiar: true) { inserir(Relacionamentos::CampoPreenchido, resumos_das_criadas(importacao, linhas, ids)) }
    end
    quantas / UMA_RECUSA_A_CADA
  end

  # `quantas` pessoas que a conta já tinha, uma linha cada, com três campos que a lista preencheu: e-mail, cidade e a
  # marca de cliente. Os três estão como a lista os deixou, então os três voltam.
  def por_pessoas_completadas(importacao, quantas)
    diag_estado if diag?
    diag_plano('antes do 1o lote')
    em_lotes(importacao, quantas) do |numeros|
      pessoas = numeros.map { |numero| pessoa_completada(importacao.account_id, numero) }
      ids = diag_tempo('completadas', 'pessoas') { inserir(Contact, pessoas) }
      linhas = diag_tempo('completadas', 'linhas') { inserir_linhas(importacao, numeros, ids, ja_existia: true) }
      diag_tempo('completadas', 'campos', vigiar: true) do
        inserir(Relacionamentos::CampoPreenchido, campos_das_linhas(importacao.account_id, linhas, ids, pessoas))
      end
      diag_plano('depois do 1o lote') if numeros.first == 1
    end
  end

  # As estatísticas que o banco de produção tem (o autovacuum as mantém): sem elas o plano é o de tabela vazia.
  def atualizar_estatisticas
    ActiveRecord::Base.connection.execute('ANALYZE contacts, campaign_import_rows, relacionamentos_campos_preenchidos')
  end

  # O bloco, com quantas consultas fez (fora as de esquema e de transação), o tempo de parede e, por tabela, quantas
  # consultas e quantos segundos.
  def medir_consultas
    por_tabela = Hash.new { |tabelas, nome| tabelas[nome] = { consultas: 0, segundos: 0.0 } }
    anotar = lambda do |_evento, inicio, fim, _id, dados|
      next if dados[:cached] || %w[SCHEMA TRANSACTION].include?(dados[:name])

      da_tabela = por_tabela[tabela_da_consulta(dados[:sql])]
      da_tabela[:consultas] += 1
      da_tabela[:segundos] += fim - inicio
    end
    resultado = nil
    segundos = Benchmark.realtime { ActiveSupport::Notifications.subscribed(anotar, 'sql.active_record') { resultado = yield } }
    Medida.new(resultado: resultado, consultas: por_tabela.values.sum { |da_tabela| da_tabela[:consultas] }, segundos: segundos,
               por_tabela: por_tabela)
  end

  private

  # DIAGNÓSTICO #3092 (branch diag/3092-medicao, não mergear). Só com DIAG_3092=1.
  def diag?
    ENV['DIAG_3092'] == '1'
  end

  DIAG_TABELAS = %w[contacts campaign_import_rows relacionamentos_campos_preenchidos].freeze

  def diag_contadores
    ActiveRecord::Base.connection.select_all(
      "SELECT relname, seq_scan, idx_scan FROM pg_stat_xact_user_tables WHERE relname IN ('#{DIAG_TABELAS.join("','")}')"
    ).to_a.each_with_object({}) { |linha, total| total["#{linha['relname']}.seq"] = linha['seq_scan']; total["#{linha['relname']}.idx"] = linha['idx_scan'] }
  end

  def diag_estado
    conexao = ActiveRecord::Base.connection
    lista = DIAG_TABELAS.map { |tabela| "'#{tabela}'" }.join(',')
    DIAG_TABELAS.each { |tabela| puts "DIAG_3092 estado count #{tabela}=#{conexao.select_value("SELECT count(*) FROM #{tabela}")}" }
    conexao.select_all("SELECT relname, n_live_tup, n_dead_tup, n_tup_ins, n_tup_del FROM pg_stat_user_tables WHERE relname IN (#{lista})")
           .each { |linha| puts "DIAG_3092 estado stat #{linha.values.join(' | ')}" }
    conexao.select_all("SELECT tgrelid::regclass, tgname FROM pg_trigger WHERE NOT tgisinternal AND tgrelid::regclass::text IN (#{lista})")
           .each { |linha| puts "DIAG_3092 estado trigger #{linha.values.join(' | ')}" }
    conexao.select_all("SELECT tablename, indexname FROM pg_indexes WHERE tablename IN (#{lista}) ORDER BY 1, 2")
           .each { |linha| puts "DIAG_3092 estado indice #{linha.values.join(' | ')}" }
    conexao.select_all("SELECT pid, state, xact_start, wait_event_type, left(query, 80) FROM pg_stat_activity
                        WHERE datname = current_database() AND pid <> pg_backend_pid()")
           .each { |linha| puts "DIAG_3092 estado conexao #{linha.values.join(' | ')}" }
  end

  def diag_tempo(caso, tabela, vigiar: false)
    return yield unless diag?

    antes = diag_contadores
    vigia = diag_vigia if vigiar
    resultado = nil
    segundos = Benchmark.realtime { resultado = yield }
    vigia&.kill
    depois = diag_contadores
    delta = depois.to_h { |chave, valor| [chave, valor.to_i - antes[chave].to_i] }
    puts "DIAG_3092 caso=#{caso} tabela=#{tabela} n=#{resultado.size} s=#{segundos.round(3)} cir_xact_delta=#{delta}"
    resultado
  end

  # Outra conexão olha o banco a cada segundo enquanto os campos são gravados: espera por trava (Lock) ou não.
  def diag_vigia
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    Thread.new do
      pg = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password].presence,
                      dbname: config[:database])
      loop do
        sleep 1
        pg.exec("SELECT pid, state, wait_event_type, wait_event, left(query, 80) AS q FROM pg_stat_activity
                 WHERE datname = current_database() AND pid <> pg_backend_pid() AND state <> 'idle'").each do |linha|
          puts "DIAG_3092 vigia #{linha.values.join(' | ')}"
        end
      end
    ensure
      pg&.close
    end
  end

  def diag_plano(momento)
    return unless diag?

    conexao = ActiveRecord::Base.connection
    id = conexao.select_value('SELECT max(id) FROM campaign_import_rows').to_i
    sql = 'SELECT 1 FROM ONLY campaign_import_rows x WHERE id = $1 FOR KEY SHARE OF x'
    custom = conexao.select_values("EXPLAIN (ANALYZE, BUFFERS) #{sql.sub('$1', id.to_s)}")
    conexao.execute("SET LOCAL plan_cache_mode = force_generic_plan; PREPARE diag_ri(bigint) AS #{sql}")
    generico = conexao.select_values("EXPLAIN EXECUTE diag_ri(#{id})")
    conexao.execute('DEALLOCATE diag_ri; SET LOCAL plan_cache_mode = auto')
    estat = conexao.select_one("SELECT reltuples, relpages FROM pg_class WHERE relname = 'campaign_import_rows'")
    puts "DIAG_3092 plano #{momento} pg_class=#{estat}\n  custom: #{custom.join(' / ')}\n  generico: #{generico.join(' / ')}"
  end

  def em_lotes(importacao, quantas, &)
    primeiro = importacao.campaign_import_rows.maximum(:row_number).to_i + 1
    (primeiro...(primeiro + quantas)).each_slice(LOTE, &)
  end

  def pessoa_criada(conta_id, numero)
    carimbos.merge(account_id: conta_id, name: "Pessoa Criada #{numero}", phone_number: format('+5511%09d', 900_000_000 + numero),
                   opted_out_at: (Time.current if (numero % UMA_RECUSA_A_CADA).zero?))
  end

  def pessoa_completada(conta_id, numero)
    carimbos.merge(account_id: conta_id, name: "Pessoa Antiga #{numero}", email: "pessoa.antiga.#{numero}@exemplo.com.br",
                   additional_attributes: { 'city' => CIDADE }, contact_type: Contact.contact_types[:customer], customer_since: CLIENTE_DESDE)
  end

  def inserir_linhas(importacao, numeros, ids, ja_existia:)
    linhas = numeros.zip(ids).map do |numero, id|
      carimbos.merge(campaign_import_id: importacao.id, row_number: numero, contact_id: id, was_existing_contact: ja_existia,
                     status: CampaignImportRow.statuses[:imported])
    end
    inserir(CampaignImportRow, linhas)
  end

  # O resumo de cada pessoa como está no banco (Relacionamentos::Trazer::PessoaCriada), na linha que a criou.
  def resumos_das_criadas(importacao, linhas, ids)
    campo = Relacionamentos::CampoPreenchido
    como_estao = Relacionamentos::Trazer::PessoaCriada.new(importacao).conteudos(ids)
    linhas.zip(ids).map do |linha, id|
      carimbos.merge(account_id: importacao.account_id, campaign_import_row_id: linha, contact_id: id, campo: campo::PESSOA_CRIADA,
                     valor_posto_hash: campo.resumo(linha, campo::PESSOA_CRIADA, como_estao.fetch(id)))
    end
  end

  def campos_das_linhas(conta_id, linhas, ids, pessoas)
    campo = Relacionamentos::CampoPreenchido
    linhas.zip(ids, pessoas).flat_map do |linha, id, pessoa|
      postos = { 'email' => pessoa[:email], campo::CIDADE => CIDADE, campo::CLIENTE => campo.instante(CLIENTE_DESDE) }
      postos.map do |nome, valor|
        carimbos.merge(account_id: conta_id, campaign_import_row_id: linha, contact_id: id, campo: nome,
                       valor_posto_hash: campo.resumo(linha, nome, valor), tipo_anterior: (Contact.contact_types[:lead] if nome == campo::CLIENTE))
      end
    end
  end

  # Devolve os ids, na ordem em que as linhas foram passadas.
  def inserir(modelo, linhas)
    modelo.insert_all!(linhas, returning: %w[id]).rows.flatten # rubocop:disable Rails/SkipsModelValidations -- dezenas de milhares de linhas
  end

  def carimbos
    agora = Time.current
    { created_at: agora, updated_at: agora }
  end

  # A tabela de onde a consulta lê: a primeira palavra depois de FROM, sem as aspas.
  def tabela_da_consulta(sql)
    sql.split(' FROM ', 2).last.to_s.split.first.to_s.delete('"')
  end
end
