# Gera o PDF e a planilha do painel de desempenho do agente (#2226) a partir de um arquivo do contrato v2.
# Uso local, fora do app (o endpoint de verdade vem no PR da API e chama os mesmos serviços):
#
#   LOCALE=pt_BR bundle exec rails runner script/desempenho/exportar.rb <arquivo.json> <7|30|90|tudo|todos> <pasta>
#
# - <arquivo.json>: um pacote (`"pacote": true`, com os agregados de cada período e a lista de procuras) ou o painel
#   de um período só (como a fixture das specs).
# - Grava <pasta>/desempenho-<fonte>-<periodo>.pdf e .xlsx (ex.: desempenho-vida-real-30.pdf).
# - Nunca imprime conteúdo do arquivo: em erro, só a classe e a parte que faltou.
module ExportarDesempenho
  module_function

  def rodar(argumentos)
    caminho, escolha, pasta = argumentos
    abort('uso: exportar.rb <arquivo.json> <7|30|90|tudo|todos> <pasta>') if [caminho, escolha, pasta].any?(&:blank?)

    I18n.with_locale(ENV.fetch('LOCALE', 'pt_BR')) { gerar(Autonomia::Desempenho::Exportacao::Contrato.ler(caminho), escolha, pasta) }
  rescue Autonomia::Desempenho::Exportacao::Contrato::Invalido => e
    abort("#{e.class.name}: #{e.message}")
  rescue JSON::ParserError, Errno::ENOENT => e
    abort("#{e.class.name}: não consegui ler o arquivo")
  end

  def gerar(dados, escolha, pasta)
    FileUtils.mkdir_p(pasta)
    paineis(dados, escolha).each do |painel|
      base = File.join(pasta, "desempenho-#{painel.dig('meta', 'fonte').to_s.tr('_', '-')}-#{painel.dig('meta', 'periodo', 'chave')}")
      File.binwrite("#{base}.pdf", Autonomia::Desempenho::Exportacao::Pdf.new(painel).gerar)
      File.binwrite("#{base}.xlsx", Autonomia::Desempenho::Exportacao::Planilha.new(painel).gerar)
      puts "#{base}.pdf e .xlsx (#{Array(painel['procuras']).size} procuras no período)"
    end
  end

  def paineis(dados, escolha)
    return [Autonomia::Desempenho::Exportacao::Contrato.validar!(dados)] unless dados['pacote']

    chaves = escolha == 'todos' ? Autonomia::Desempenho::Exportacao::Contrato::PERIODOS : [escolha]
    chaves.map { |chave| Autonomia::Desempenho::Exportacao::Contrato.do_pacote(dados, chave) }
  end
end

ExportarDesempenho.rodar(ARGV)
