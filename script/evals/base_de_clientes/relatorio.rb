# Grava o resultado da bateria (#1246): resultados.json com tudo e RELATORIO.md para ler.
class BaseDeClientesEval::Relatorio
  ORDEM = %w[critico sugestao_errada_confiante sugestao_errada parou_com_erro perguntou_a_toa perfeito].freeze

  def initialize(resultados, gasto:, chamadas:, tokens:)
    @resultados = resultados
    @gasto = gasto
    @chamadas = chamadas
    @tokens = tokens
  end

  def gravar(pasta)
    File.write(pasta.join('resultados.json'), JSON.pretty_generate(@resultados))
    File.write(pasta.join('RELATORIO.md'), markdown)
  end

  private

  def jev
    @resultados.select { |resultado| resultado[:motor] == 'jev' }
  end

  def sem_jev
    @resultados.select { |resultado| resultado[:motor] == 'sem_jev' }
  end

  def markdown
    [cabecalho, placar('Com o Jev', jev), placar('Sem o Jev (só os apelidos de cabeçalho)', sem_jev), tabela, problemas].join("\n\n")
  end

  def cabecalho
    <<~MD.strip
      # Bateria de planilhas — base de clientes (#1246)

      Rodada de #{Time.current.strftime('%d/%m/%Y %H:%M')} · modelo #{TypesafeAi::Config.model} · #{@chamadas} chamadas ao Jev ·
      #{@tokens} tokens · **gasto US$ #{format('%.4f', @gasto)}**
    MD
  end

  def placar(titulo, lista)
    return "## #{titulo}\n\nSem resultados." if lista.empty?

    contagem = lista.pluck(:veredicto).tally
    linhas = ORDEM.filter_map { |veredicto| "| #{veredicto} | #{contagem[veredicto]} |" if contagem[veredicto] }
    "## #{titulo} (#{lista.size} leituras)\n\n| Veredicto | Leituras |\n|---|---|\n#{linhas.join("\n")}"
  end

  def tabela
    linhas = jev.group_by { |resultado| resultado[:caso] }.map do |caso, leituras|
      base = sem_jev.find { |resultado| resultado[:caso] == caso }
      "| #{caso} | #{leituras.first[:nivel]} | #{leituras.first[:titulo]} | #{veredictos(leituras)} | #{base&.dig(:veredicto)} | " \
        "#{linhas_texto(leituras.first)} | #{leituras.filter_map { |leitura| leitura[:segundos] }.max} |"
    end
    "## Por caso\n\n| Caso | Nível | Planilha | Com Jev | Sem Jev | Linhas alcançadas / uma pessoa alcançaria | Seg. |\n" \
      "|---|---|---|---|---|---|---|\n#{linhas.join("\n")}"
  end

  def veredictos(leituras)
    leituras.pluck(:veredicto).tally.map { |veredicto, total| total > 1 ? "#{veredicto} ×#{total}" : veredicto }.join(', ')
  end

  def linhas_texto(resultado)
    linhas = resultado[:linhas]
    return '—' unless linhas

    texto = "#{linhas[:validas]} / #{resultado[:alcance_humano]}"
    texto += " (#{linhas[:repetidas]} repetidas)" if linhas[:repetidas].positive?
    texto
  end

  def problemas
    itens = jev.reject { |resultado| resultado[:veredicto] == 'perfeito' }.uniq { |resultado| [resultado[:caso], resultado[:veredicto]] }
    return "## Problemas\n\nNenhum." if itens.empty?

    "## Problemas\n\n#{itens.map { |resultado| problema(resultado) }.join("\n")}"
  end

  def problema(resultado)
    return "- **#{resultado[:caso]}** #{resultado[:titulo]}: parou com `#{resultado[:erro]}`" if resultado[:erro]

    alvos = resultado[:alvos].filter_map do |alvo, dados|
      next if dados[:classe] == 'certo'

      "#{alvo}: #{dados[:classe]} (esperado #{dados[:esperado].inspect}, veio #{dados[:obtido].inspect}, confiança #{dados[:confianca]})"
    end
    cabecalho = resultado[:cabecalho_ok] == false ? ' · cabeçalho/aba errados' : ''
    "- **#{resultado[:caso]}** #{resultado[:titulo]} → #{resultado[:veredicto]}#{cabecalho} · perguntou: #{resultado[:perguntou]} · " \
      "Jev #{resultado[:jev].inspect} · #{alvos.join('; ')}"
  end
end
