# Grava o resultado da bateria (#1246): resultados.json com tudo e RELATORIO.md para ler, com a
# leitura nova (flag customer_base) ao lado da clássica (sem a flag, igual ao main).
class BaseDeClientesEval::Relatorio
  ORDEM = %w[critico sugestao_errada_confiante sugestao_errada parou_com_erro perguntou_a_toa perfeito].freeze
  MOTORES = { 'nova' => 'Leitura nova (customer_base)', 'classica' => 'Leitura clássica (sem a flag)' }.freeze

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

  def do_motor(motor)
    @resultados.select { |resultado| resultado[:motor] == motor }
  end

  def markdown
    placares = MOTORES.filter_map { |motor, titulo| placar(titulo, do_motor(motor)) if do_motor(motor).any? }
    [cabecalho, *placares, tabela, problemas].join("\n\n")
  end

  def cabecalho
    <<~MD.strip
      # Bateria de planilhas — base de clientes (#1246)

      Rodada de #{Time.current.strftime('%d/%m/%Y %H:%M')} · modelo #{TypesafeAi::Config.model} · #{@chamadas} chamadas ao Jev ·
      #{@tokens} tokens · **gasto US$ #{format('%.4f', @gasto)}**
    MD
  end

  def placar(titulo, lista)
    contagem = lista.pluck(:veredicto).tally
    linhas = ORDEM.filter_map { |veredicto| "| #{veredicto} | #{contagem[veredicto]} |" if contagem[veredicto] }
    "## #{titulo} (#{lista.size} leituras)\n\n| Veredicto | Leituras |\n|---|---|\n#{linhas.join("\n")}\n\n#{linhas_do_placar(lista)}"
  end

  # Linhas da primeira repetição de cada caso (as linhas não dependem da repetição, só as colunas).
  def linhas_do_placar(lista)
    primeiras = lista.select { |resultado| resultado[:repeticao] == 1 }
    soma = ->(chave) { primeiras.sum { |resultado| resultado.dig(:linhas, chave) || 0 } }
    alcance = primeiras.sum { |resultado| resultado[:alcance_humano] }
    acertos = soma.call(:validas) - soma.call(:inventadas)
    "Linhas: #{acertos} de #{alcance} alcançadas · perdidas #{alcance - acertos} · **inventadas #{soma.call(:inventadas)}**"
  end

  def tabela
    linhas = @resultados.group_by { |resultado| resultado[:caso] }.map do |caso, leituras|
      nova = leituras.select { |leitura| leitura[:motor] == 'nova' }
      classica = leituras.select { |leitura| leitura[:motor] == 'classica' }
      "| #{caso} | #{leituras.first[:nivel]} | #{leituras.first[:titulo]} | #{veredictos(nova)} | #{linhas_texto(nova.first)} | " \
        "#{veredictos(classica)} | #{linhas_texto(classica.first)} |"
    end
    "## Por caso\n\n| Caso | Nível | Planilha | Nova | Linhas (nova) | Clássica | Linhas (clássica) |\n" \
      "|---|---|---|---|---|---|---|\n#{linhas.join("\n")}"
  end

  def veredictos(leituras)
    return '—' if leituras.empty?

    leituras.pluck(:veredicto).tally.map { |veredicto, total| total > 1 ? "#{veredicto} ×#{total}" : veredicto }.join(', ')
  end

  def linhas_texto(resultado)
    linhas = resultado&.dig(:linhas)
    return '—' unless linhas

    texto = "#{linhas[:validas] - linhas[:inventadas]} / #{resultado[:alcance_humano]}"
    texto += " (**#{linhas[:inventadas]} inventadas**)" if linhas[:inventadas].positive?
    texto += " (#{linhas[:repetidas]} repetidas)" if linhas[:repetidas].positive?
    texto
  end

  def problemas
    itens = do_motor('nova').reject { |resultado| resultado[:veredicto] == 'perfeito' }
                            .uniq { |resultado| [resultado[:caso], resultado[:veredicto]] }
    return "## Problemas da leitura nova\n\nNenhum." if itens.empty?

    "## Problemas da leitura nova\n\n#{itens.map { |resultado| problema(resultado) }.join("\n")}"
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
