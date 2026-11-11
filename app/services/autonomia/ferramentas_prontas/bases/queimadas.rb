# FOCOS DE QUEIMADA (#2858, F5): os focos de calor detectados por satélite do Programa Queimadas do INPE, dos últimos
# `DIAS` dias (o de hoje até onde já saiu). Diária.
#   - um CSV por dia (`focos_diario_br_AAAAMMDD.csv`, ~1 MB e ~8 mil focos num dia de seca), separado por ",", em UTF-8;
#     cada rodada baixa a janela inteira de novo, porque o arquivo do dia corrente cresce ao longo do dia;
#   - o dia que ainda não saiu (404) é pulado; os outros, se falharem, derrubam a rodada (a janela vale inteira);
#   - fica: quando, a coordenada, o código IBGE do município, o bioma e o satélite. Nada de pessoa.
class Autonomia::FerramentasProntas::Bases::Queimadas < Autonomia::FerramentasProntas::Bases::Importador
  CHAVE = 'queimadas'.freeze
  MODELO = Autonomia::FerramentasProntas::Bases::FocoDeQueimada
  HOSTS = %w[dataserver-coids.inpe.br].freeze
  FREQUENCIA = :diaria
  MINIMO = 100
  # Queimada varia de verdade (a chuva apaga, a seca acende): a janela nova pode vir bem menor que a anterior.
  FRACAO_MINIMA = nil
  # A base envelhece em 1 dia (a ferramenta passa a dizer "não consegui"): falhou, tenta de novo no mesmo dia.
  NOVA_TENTATIVA_NO_DIA = true
  DIAS = 8
  PASTA = 'https://dataserver-coids.inpe.br/queimadas/queimadas/focos/csv/diario/Brasil'.freeze
  MAX_BYTES = 30.megabytes
  PRAZO = 120
  COLUNAS = %w[detectado_em latitude longitude codigo_municipio bioma satelite].freeze
  CABECALHO = %w[lat lon data_hora_gmt satelite municipio_id bioma].freeze

  class << self
    def dias(agora = Time.current)
      hoje = agora.utc.to_date
      (0...DIAS).map { |atras| hoje - atras }
    end

    def endereco(dia)
      "#{PASTA}/focos_diario_br_#{dia.strftime('%Y%m%d')}.csv"
    end

    def baixar(download)
      dias.each_with_object({}) do |dia, arquivos|
        arquivo = download.baixar(endereco(dia), max_bytes: MAX_BYTES, prazo: PRAZO, nao_encontrado: :nil)
        arquivos[dia] = arquivo if arquivo
      end
    end

    def linhas(arquivos)
      leitores = arquivos.values.map { |arquivo| csv(arquivo, colunas: CABECALHO, separador: ',') }
      Enumerator.new do |saida|
        leitores.each { |leitor| leitor.each { |linha| saida << foco(linha) } }
      end
    end

    def foco(linha)
      latitude = Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada(linha['lat'], 90)
      longitude = Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada(linha['lon'], 180)
      detectado = quando(linha['data_hora_gmt'])
      return unless latitude && longitude && detectado

      [detectado, latitude, longitude, digitos(linha['municipio_id']), texto(linha['bioma']), texto(linha['satelite'])]
    end

    # "2026-11-10 13:40:00", em UTC.
    def quando(valor)
      Time.find_zone('UTC').strptime(valor.to_s.strip, '%Y-%m-%d %H:%M:%S')
    rescue ArgumentError
      nil
    end
  end
end
