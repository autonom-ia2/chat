# AERONAVES (#2858, F5): o Registro Aeronáutico Brasileiro (RAB) da ANAC, uma linha por matrícula. Diário.
#   - um CSV (`dados_aeronaves.csv`, ~24 MB, ~35 mil aeronaves), separado por ";", em UTF-8, que abre com uma linha
#     "Atualizado em: AAAA-MM-DD" antes do cabeçalho;
#   - proprietários e operadores vêm num JSON dentro da coluna, com nome e documento. PESSOA FÍSICA NUNCA ENTRA: só fica
#     quem tem CNPJ válido (empresa), com nome e CNPJ; o resto vira só a contagem (`outros_proprietarios`), sem nome,
#     sem CPF e sem UF;
#   - os gravames ("ALIENAÇÃO FIDUCIÁRIA / ARRENDAMENTO OPERACIONAL") viram lista, um por item.
# A matrícula se repete em poucas linhas no arquivo da ANAC: ficam todas, e a busca devolve todas.
class Autonomia::FerramentasProntas::Bases::Aeronaves < Autonomia::FerramentasProntas::Bases::Importador
  CHAVE = 'aeronaves'.freeze
  MODELO = Autonomia::FerramentasProntas::Bases::Aeronave
  HOSTS = %w[sistemas.anac.gov.br].freeze
  FREQUENCIA = :diaria
  MINIMO = 10_000
  ARQUIVO = 'https://sistemas.anac.gov.br/dadosabertos/Aeronaves/RAB/dados_aeronaves.csv'.freeze
  MAX_BYTES = 100.megabytes
  PRAZO = 600
  COLUNAS = %w[matricula dados].freeze
  CABECALHO = %w[MARCAS PROPRIETARIOS OPERADORES NR_SERIE DS_MODELO NM_FABRICANTE CD_TIPO_ICAO NR_PASSAGEIROS_MAX NR_ASSENTOS
                 NR_ANO_FABRICACAO NR_PMD DT_VALIDADE_CA DT_CANC DS_MOTIVO_CANC DS_GRAVAME TP_MOTOR TP_OPERACAO
                 DS_CATEGORIA_HOMOLOGACAO].freeze
  PREAMBULO = 'Atualizado em'.freeze
  INDISPONIVEL = 'Indisponível'.freeze

  class << self
    def baixar(download)
      { rab: download.baixar(ARQUIVO, max_bytes: MAX_BYTES, prazo: PRAZO) }
    end

    def linhas(arquivos)
      rab = csv(arquivos.fetch(:rab), colunas: CABECALHO, preambulo: PREAMBULO)
      Enumerator.new do |saida|
        rab.each do |linha|
          matricula = matricula(linha['MARCAS'])
          saida << [matricula, aeronave(linha).to_json] if matricula
        end
      end
    end

    # "PR-ABC", "pr abc" -> "PRABC"; nil quando não tem 5 letras ou números começando por P (as marcas do Brasil).
    def matricula(valor)
      texto = valor.to_s.upcase.delete('^A-Z0-9')
      texto if texto.length == 5 && texto.start_with?('P')
    end

    # Os campos de texto que vão como estão: nome no arquivo da ANAC -> nome na resposta.
    FICHA = {
      'NM_FABRICANTE' => 'fabricante', 'DS_MODELO' => 'modelo', 'CD_TIPO_ICAO' => 'tipo_icao', 'NR_SERIE' => 'numero_de_serie',
      'NR_ANO_FABRICACAO' => 'ano_de_fabricacao', 'NR_ASSENTOS' => 'assentos', 'NR_PASSAGEIROS_MAX' => 'passageiros_no_maximo',
      'NR_PMD' => 'peso_maximo_de_decolagem_kg', 'TP_MOTOR' => 'motor', 'DS_CATEGORIA_HOMOLOGACAO' => 'categoria',
      'TP_OPERACAO' => 'operacao', 'DS_MOTIVO_CANC' => 'motivo_do_cancelamento'
    }.freeze

    def aeronave(linha)
      FICHA.to_h { |coluna, nome| [nome, texto(linha[coluna])] }.merge(registro(linha), donos(linha)).compact_blank
    end

    def registro(linha)
      { 'certificado_de_aeronavegabilidade_valido_ate' => data_compacta(linha['DT_VALIDADE_CA']),
        'situacao' => linha['DT_CANC'].to_s.strip.empty? ? 'registrada' : 'cancelada',
        'cancelada_em' => data(linha['DT_CANC'])&.iso8601, 'gravames' => gravames(linha['DS_GRAVAME']) }
    end

    def donos(linha)
      proprietarios, outros_proprietarios = pessoas(linha['PROPRIETARIOS'])
      operadores, outros_operadores = pessoas(linha['OPERADORES'])
      { 'proprietarios_empresas' => proprietarios, 'outros_proprietarios' => outros_proprietarios,
        'operadores_empresas' => operadores, 'outros_operadores' => outros_operadores }
    end

    # -> [empresas (nome, CNPJ, UF), quantas pessoas sem CNPJ]. "Indisponível" não conta como ninguém.
    def pessoas(json)
      lista = JSON.parse(json.to_s)
      lista = [] unless lista.is_a?(Array)
      informadas = lista.select { |item| item.is_a?(Hash) && item['DOCUMENTO'].to_s.strip != INDISPONIVEL }
      empresas = informadas.filter_map { |item| empresa(item) }
      [empresas, informadas.size - empresas.size]
    rescue JSON::ParserError
      [[], 0]
    end

    def empresa(item)
      cnpj = Autonomia::FerramentasProntas::Parametro.cnpj(item['DOCUMENTO'])
      return if cnpj.nil?

      { 'nome' => texto(item['NOME']), 'cnpj' => cnpj, 'uf' => texto(item['UF']) }.compact
    end

    def gravames(valor)
      valor.to_s.split('/').map(&:squish).compact_blank.uniq
    end

    # "03112027" -> "2027-11-03".
    def data_compacta(valor)
      texto = valor.to_s.strip
      return if texto.length != 8 || texto.delete('0-9').present?

      Date.new(texto[4, 4].to_i, texto[2, 2].to_i, texto[0, 2].to_i).iso8601
    rescue Date::Error
      nil
    end
  end
end
