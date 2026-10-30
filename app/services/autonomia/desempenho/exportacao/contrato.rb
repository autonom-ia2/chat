# Contrato v2 do painel de desempenho do agente (#2226), do lado do servidor.
#
# - `validar!(painel)`: confere a versão e as partes que os exportadores leem. O erro diz só a parte que faltou,
#   nunca o conteúdo (o arquivo traz dado de conversa).
# - `do_pacote(pacote, chave)`: o pacote guarda os agregados de cada período e a lista única de procuras. O painel
#   de um período = os agregados daquele período + o catálogo + as procuras cujo dia de início cai entre o início
#   e o fim do período (inclusivos, com a data local que já vem no texto). É a mesma regra do front
#   (`desempenhoFonte.js`), para o arquivo e a tela baterem.
class Autonomia::Desempenho::Exportacao::Contrato
  VERSAO = 2
  PERIODOS = %w[7 30 90 tudo].freeze
  PARTES = %w[
    meta kpis evolucao funil indicadores comparacoes temas cortes origem horarios qualidade pessoa quem
    conversas_ativas perdas motivos recomendacoes confianca avisos catalogo procuras
  ].freeze
  PARTES_DA_META = %w[agente periodo dados_ate fuso horario_comercial nomes base].freeze

  class Invalido < StandardError; end

  def self.validar!(painel)
    raise Invalido, 'o painel precisa ser um objeto' unless painel.is_a?(Hash)
    raise Invalido, "versao #{VERSAO} esperada, veio #{painel['versao'].inspect}" unless painel['versao'] == VERSAO

    faltando = partes_que_faltam(painel)
    raise Invalido, "faltou: #{faltando.join(', ')}" if faltando.any?

    painel
  end

  def self.partes_que_faltam(painel)
    meta = painel['meta'].is_a?(Hash) ? painel['meta'] : {}
    PARTES.reject { |parte| painel.key?(parte) } + PARTES_DA_META.reject { |parte| meta.key?(parte) }.map { |parte| "meta.#{parte}" }
  end

  def self.do_pacote(pacote, chave)
    raise Invalido, "versao #{VERSAO} esperada, veio #{pacote['versao'].inspect}" unless pacote.is_a?(Hash) && pacote['versao'] == VERSAO
    raise Invalido, "periodo desconhecido: #{chave}" unless PERIODOS.include?(chave.to_s)

    agregados = pacote.dig('periodos', chave.to_s)
    raise Invalido, "faltou: periodos.#{chave}" unless agregados.is_a?(Hash)

    validar!(agregados.merge('versao' => VERSAO, 'catalogo' => pacote['catalogo'],
                             'procuras' => procuras_do_periodo(pacote['procuras'], agregados.dig('meta', 'periodo'))))
  end

  def self.procuras_do_periodo(procuras, periodo)
    raise Invalido, 'faltou: meta.periodo' unless periodo.is_a?(Hash)

    inicio = periodo['inicio'].to_s
    fim = periodo['fim'].to_s
    Array(procuras).select { |procura| dia(procura['inicio']).between?(inicio, fim) }
  end

  # 'AAAA-MM-DDTHH:mm' -> 'AAAA-MM-DD', sem passar por Date/UTC (o texto já está no fuso da conta).
  def self.dia(data_hora)
    data_hora.to_s.first(10)
  end

  def self.ler(caminho)
    JSON.parse(File.read(caminho))
  end
end
