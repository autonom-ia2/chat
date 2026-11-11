# Gera as tabelas do relatório (markdown) a partir de tmp/stress/fase-<X>/resultado.json. Ruby puro, sem Rails e sem
# IA: só lê o JSON. Uso: ruby script/stress/multifunil/tabelas.rb tmp/stress/fase-A/resultado.json [rotulo]
require 'json'

module Stress; end

class Stress::Tabelas
  IAS = { 'assunto' => %w[assunto assunto_revisao], 'movimentacao' => %w[avaliacao_card] }.freeze
  NOMES = { 'assunto' => 'IA de assunto (Jev + revisão)', 'movimentacao' => 'IA de movimentação (avaliação do card)' }.freeze
  CABECALHO = '| Conversa | Cen. | Variação | Esperado | Obtido (só o que diferiu) | Resultado | Latência IA s (assunto / mov.) | Custo US$ |'.freeze

  def initialize(caminho, rotulo)
    @dados = JSON.parse(File.read(caminho))
    @rotulo = rotulo || "Fase #{@dados['fase']}"
    @conversas = @dados['conversas']
  end

  def gerar
    [resumo, por_conversa, por_ia, por_cenario, custos, estabilidade].join("\n\n")
  end

  private

  def resumo
    passaram = @conversas.count { |c| c['passou'] }
    "### #{@rotulo}: #{passaram} de #{@conversas.size} execuções passaram (#{pct(passaram, @conversas.size)}). " \
      "Gasto registrado: US$ #{format('%.4f', @dados['gasto_fase_usd'])}."
  end

  def por_conversa
    [CABECALHO, '|---|---|---|---|---|---|---|---|', *@conversas.map { |c| linha(c) }].join("\n")
  end

  def linha(conversa)
    resultado = conversa['passou'] ? 'PASSOU' : 'FALHOU'
    "| #{conversa['id']} r#{conversa['rodada']} | #{conversa['cenario']} | #{conversa['variacao']} | #{esperado(conversa)} | " \
      "#{obtido(conversa)} | #{resultado} | #{latencia(conversa)} | #{format('%.4f', conversa['custo_usd'].to_f)} |"
  end

  def obtido(conversa)
    return conversa['erro_do_harness'] if conversa['erro_do_harness']

    falhas = Array(conversa['checagens']).reject { |k| k['ok'] }
    return 'igual ao esperado' if falhas.empty?

    falhas.map { |k| "#{k['tipo']}: #{curto(k['obtido'])}" }.join('; ')
  end

  def esperado(conversa)
    Array(conversa['checagens']).reject { |k| k['ia'] == 'sistema' || k['tipo'].end_with?('_respondeu') }
                                .map { |k| curto(k['esperado']) }.join('; ')
  end

  def por_ia
    linhas = IAS.keys.map do |ia|
      checagens = @conversas.flat_map { |c| Array(c['checagens']) }.select { |k| k['ia'] == ia }
      certas = checagens.count { |k| k['ok'] }
      "| #{NOMES[ia]} | #{certas}/#{checagens.size} | #{pct(certas, checagens.size)} |"
    end
    ['| IA | Checagens certas | Acerto |', '|---|---|---|', *linhas].join("\n")
  end

  def por_cenario
    linhas = @conversas.group_by { |c| c['cenario'] }.sort.map do |cenario, lista|
      certas = lista.count { |c| c['passou'] }
      "| #{cenario} | #{certas}/#{lista.size} | #{pct(certas, lista.size)} |"
    end
    ['| Cenário | Execuções que passaram | Acerto |', '|---|---|---|', *linhas].join("\n")
  end

  def custos
    linhas = IAS.map do |ia, features|
      total = soma_final(features)
      "| #{NOMES[ia]} | #{format('%.4f', total)} | #{chamadas(features)} | #{format('%.5f', por_mensagem(total))} |"
    end
    ["Mensagens do cliente processadas: #{mensagens_do_cliente}.", '',
     '| IA | Custo US$ | Chamadas | Custo médio por mensagem do cliente US$ |', '|---|---|---|---|', *linhas].join("\n")
  end

  def soma_final(features)
    @conversas.sum { |c| features.sum { |f| c.dig('final', 'custo_por_feature', f).to_f } }
  end

  def chamadas(features)
    @conversas.sum { |c| Array(c['turnos']).sum { |t| features.sum { |f| t.fetch('chamadas', {})[f].to_i } } }
  end

  def mensagens_do_cliente
    @mensagens_do_cliente ||= @conversas.sum { |c| Array(c['turnos']).size }
  end

  def por_mensagem(total)
    mensagens_do_cliente.zero? ? 0 : total / mensagens_do_cliente
  end

  # Mesma conversa em várias rodadas: passou em todas, em nenhuma ou às vezes (instável).
  def estabilidade
    grupos = @conversas.group_by { |c| c['id'] }
    instaveis = grupos.select { |_id, lista| lista.map { |c| c['passou'] }.uniq.size > 1 }.keys
    "Rodadas por conversa: #{grupos.values.map(&:size).max}. Instáveis (o resultado mudou entre rodadas): " \
      "#{instaveis.empty? ? 'nenhuma' : instaveis.join(', ')}."
  end

  def latencia(conversa)
    soma = Hash.new(0.0)
    Array(conversa['turnos']).each { |t| t.fetch('latencia_ia_s', {}).each { |ia, s| soma[ia] += s.to_f } }
    "#{soma['assunto'].round(1)} / #{soma['movimentacao'].round(1)}"
  end

  def curto(valor)
    texto = valor.is_a?(String) ? valor : JSON.generate(valor)
    texto = texto.delete('"{}').gsub('tipo:', '').tr('|', '/')
    texto.length > 140 ? "#{texto[0, 137]}..." : texto
  end

  def pct(parte, total)
    total.zero? ? '-' : "#{(100.0 * parte / total).round}%"
  end
end

puts Stress::Tabelas.new(ARGV.fetch(0), ARGV[1]).gerar
