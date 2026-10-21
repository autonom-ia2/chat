# Testa as migrations novas de um lote do jeito que o deploy as roda (#2024).
#
# O CI comum carrega o schema.rb e nunca roda migration. Aqui o banco parte do schema.rb da base (a main de antes do
# PR ou da rodada da fila), as migrations novas rodam pelo mesmo caminho do `db:migrate` da green (com os bloqueios do
# strong_migrations) e quatro coisas são conferidas:
#   1. o código anterior aguenta o schema novo (Compatibilidade);
#   2. o down de cada migration, da última para a primeira, devolve a estrutura da base;
#   3. o up de novo chega à mesma estrutura;
#   4. o schema.rb do PR é a estrutura que as migrations produzem.
# Migration irreversível (down levanta ActiveRecord::IrreversibleMigration) para o teste do down nela e sai no
# relatório: a volta do banco dela é o snapshot.
#
# Apaga e recria o banco configurado. Só roda no ambiente de teste e com o nome do banco repetido em `banco:`.
class MigrationsSeguras::Lote
  Etapa = Struct.new(:nome, :ok, :detalhe, keyword_init: true)

  # descidas: as que tiveram o down testado; irreversiveis: as que pararam o teste do down.
  Resultado = Struct.new(:migrations, :compatibilidade, :etapas, :descidas, :irreversiveis, keyword_init: true) do
    def ok?
      etapas.all?(&:ok) && (compatibilidade.nil? || compatibilidade.compativel?)
    end

    def markdown
      MigrationsSeguras::Relatorio.new(self).markdown
    end
  end

  def initialize(base_schema:, base_migrations:, retiradas:, banco:, schema_do_pr: Rails.root.join('db/schema.rb').to_s)
    @base_schema = base_schema
    @base_migrations = base_migrations.map { |caminho| File.basename(caminho) }
    @retiradas = retiradas
    @schema_do_pr = schema_do_pr
    @db_config = ActiveRecord::Base.connection_db_config
    conferir_banco!(banco)
  end

  def executar
    recriar_com(@base_schema)
    ConfigLoader.new.process
    novas = migrations_novas
    return sem_migration_nova if novas.empty?

    deixar_pendentes(novas)
    checando_todas { testar(novas) }
  end

  private

  def conferir_banco!(banco)
    raise ArgumentError, 'migrations_seguras só roda no ambiente de teste' unless Rails.env.test?
    return if banco.present? && banco == @db_config.database

    raise ArgumentError, "o banco configurado é #{@db_config.database}; repita o nome dele para confirmar que pode apagá-lo"
  end

  # schema.rb mudou sem migration nova: ele tem de continuar descrevendo a estrutura da base.
  def sem_migration_nova
    resultado = Resultado.new(migrations: [], etapas: [], descidas: [], irreversiveis: [])
    base = retrato
    etapa(resultado, 'schema.rb do PR igual ao da base (não há migration nova)') do
      recriar_com(@schema_do_pr)
      igual!(base, retrato)
    end
    resultado
  end

  # Aqui só rodam as migrations novas do lote: todas passam pelos bloqueios, mesmo com versão abaixo do start_after.
  def checando_todas
    anterior = StrongMigrations.start_after
    StrongMigrations.start_after = 0
    yield
  ensure
    StrongMigrations.start_after = anterior
  end

  def testar(novas)
    resultado = Resultado.new(migrations: novas, etapas: [], descidas: [], irreversiveis: [])
    antes = retrato
    estados = []
    subiu = etapa(resultado, 'up do lote sobre a base, uma por vez na ordem das versões') do
      novas.each do |migration|
        subir(migration)
        estados << retrato
      end
    end
    return resultado unless subiu

    depois = estados.last
    resultado.compatibilidade = compatibilidade_de_cada_prefixo(antes, estados)
    testar_volta(resultado, novas, antes, depois)
    etapa(resultado, 'schema.rb do PR igual ao que as migrations produzem') do
      recriar_com(@schema_do_pr)
      igual!(depois, retrato)
    end
    resultado
  end

  def testar_volta(resultado, novas, antes, depois)
    ok = etapa(resultado, 'down do lote, da última para a primeira') do
      novas.reverse_each do |migration|
        break unless descer(migration, resultado)

        resultado.descidas << migration
      end
    end
    return unless ok

    # Com uma irreversível no caminho, o down parou nela e a estrutura não volta à base.
    etapa(resultado, 'estrutura depois do down igual à da base') { igual!(antes, retrato) } if resultado.irreversiveis.empty?
    etapa(resultado, 'up de novo chega à mesma estrutura') do
      contexto.migrate
      igual!(depois, retrato)
    end
  end

  # O lote pode parar no meio (lock_timeout, erro), e a blue fica no schema daquele ponto. Por isso o código anterior
  # tem de aguentar o estado depois de cada migration, não só o final.
  def compatibilidade_de_cada_prefixo(antes, estados)
    verificacoes = estados.map do |estado|
      MigrationsSeguras::Compatibilidade.new(antes: antes, depois: estado, retiradas: @retiradas)
    end
    final = verificacoes.last
    verificacoes[0...-1].each { |verificacao| final.incorporar(verificacao) }
    final
  end

  # O erro do Rails não diz qual migration falhou; o relatório diz.
  def subir(migration)
    contexto.run(:up, migration.version)
  rescue StandardError => e
    raise e.class, "#{migration.version} #{migration.name}: #{e.message}", e.backtrace
  end

  def descer(migration, resultado)
    contexto.run(:down, migration.version)
    true
  rescue StandardError => e
    raise unless irreversivel?(e)

    resultado.irreversiveis << migration
    false
  end

  def irreversivel?(erro)
    [erro, erro.cause].any?(ActiveRecord::IrreversibleMigration)
  end

  def etapa(resultado, nome)
    yield
    resultado.etapas << Etapa.new(nome: nome, ok: true)
    true
  rescue StandardError => e
    resultado.etapas << Etapa.new(nome: nome, ok: false, detalhe: e.message.strip)
    false
  end

  def retrato
    MigrationsSeguras::Estrutura.capturar
  end

  def igual!(esperado, obtido)
    diferencas = MigrationsSeguras::Estrutura.diferencas(esperado, obtido)
    raise "estrutura diferente em: #{diferencas.first(20).join(', ')}" if diferencas.any?
  end

  def recriar_com(schema)
    ActiveRecord::Tasks::DatabaseTasks.purge(@db_config)
    ActiveRecord::Tasks::DatabaseTasks.load_schema(@db_config, :ruby, schema)
    @contexto = nil
  end

  def contexto
    @contexto ||= ActiveRecord::Base.connection_pool.migration_context
  end

  def migrations_novas
    contexto.migrations.reject { |migration| @base_migrations.include?(File.basename(migration.filename)) }
  end

  # O schema.rb da base marca como aplicada toda migration até a versão dele, inclusive uma nova com versão menor.
  # Na produção o que vale é a lista real: as da base aplicadas, as novas pendentes.
  def deixar_pendentes(novas)
    tabela = ActiveRecord::Base.connection_pool.schema_migration
    aplicadas = tabela.versions
    contexto.migrations.each do |migration|
      versao = migration.version.to_s
      if novas.include?(migration)
        tabela.delete_version(versao) if aplicadas.include?(versao)
      elsif aplicadas.exclude?(versao)
        tabela.create_version(versao)
      end
    end
  end
end
