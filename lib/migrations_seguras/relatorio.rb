# Relatório em Markdown do teste do lote (#2024), para o log e o Step Summary do CI. Só leva nome de migration, de
# tabela e de coluna, que já estão no repositório público; nada do banco de produção passa por aqui.
class MigrationsSeguras::Relatorio
  def initialize(resultado)
    @resultado = resultado
  end

  def markdown
    return [cabecalho, "Nenhuma migration nova em relação à base.\n", etapas].join("\n") if @resultado.migrations.empty?

    [cabecalho, migrations, etapas, achados('Bloqueios', bloqueios), achados('Avisos (não bloqueiam)', avisos), dados].join("\n")
  end

  private

  def cabecalho
    veredito = @resultado.ok? ? 'pode subir junto com as outras do lote' : 'NÃO pode subir'
    "## Migrations do lote: #{veredito}\n"
  end

  def migrations
    linhas = @resultado.migrations.map do |migration|
      "| #{migration.version} | #{migration.name} | #{volta(migration)} | #{mexe_em_dados(migration)} |"
    end
    "#{(['| Versão | Migration | Volta | Mexe em dados |', '|---|---|---|---|'] + linhas).join("\n")}\n"
  end

  def volta(migration)
    return 'irreversível (volta = snapshot)' if @resultado.irreversiveis.include?(migration)
    return 'down testado' if @resultado.descidas.include?(migration)

    'down não testado'
  end

  def mexe_em_dados(migration)
    @resultado.dados.key?(migration.version) ? 'sim: revisão humana' : 'não'
  end

  def etapas
    linhas = @resultado.etapas.map do |etapa|
      detalhe = etapa.detalhe.present? ? "\n\n```\n#{etapa.detalhe.truncate(4000)}\n```\n" : ''
      "- #{etapa.ok ? 'ok' : 'FALHOU'}: #{etapa.nome}#{detalhe}"
    end
    "### Etapas\n\n#{linhas.join("\n")}\n"
  end

  def achados(titulo, lista)
    return '' if lista.empty?

    "### #{titulo}\n\n#{lista.map { |achado| "- #{achado}" }.join("\n")}\n"
  end

  # O job confere estrutura, não o que um UPDATE faz com as linhas: isso fica com a revisão humana.
  def dados
    return '' if @resultado.dados.empty?

    linhas = @resultado.dados.map { |versao, motivos| "- #{versao}: #{motivos.join(', ')}" }
    "### Mexem em dados: revisão humana (o job não confere dados)\n\n#{linhas.join("\n")}\n"
  end

  def bloqueios
    @resultado.compatibilidade&.bloqueios || []
  end

  def avisos
    @resultado.compatibilidade&.avisos || []
  end
end
