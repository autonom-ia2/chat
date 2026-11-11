# TRANSPORTADORAS (#2858, F5): o Registro Nacional de Transportadores Rodoviários de Cargas (RNTRC) da ANTT, com os
# registros ATIVOS e PENDENTES (o cancelado não vem no arquivo). Mensal.
#   - o arquivo do mês muda de endereço a cada publicação: o catálogo de dados abertos da ANTT (`package_show` do
#     conjunto `rntrc`) diz qual é o CSV mais novo, e só um endereço do próprio host da ANTT é aceito;
#   - um CSV (`transportadores_rntrc_MM_AAAA.csv`, ~160 MB, ~1,2 milhão de registros), separado por ";", em
#     ISO-8859-1 (convertido para UTF-8 na leitura);
#   - todos os registros ficam (decisão do Rodrigo, 11/11): o RNTRC, a categoria, a situação, o município, a UF e as datas;
#   - o NOME e o CNPJ só da empresa (ETC) e da cooperativa (CTC) com CNPJ válido, e o nome sem nenhum CPF (o MEI leva o
#     do dono no fim). AUTÔNOMO (TAC), documento que é CPF ou categoria desconhecida: sem nome e sem documento.
class Autonomia::FerramentasProntas::Bases::Transportadoras < Autonomia::FerramentasProntas::Bases::Importador
  CHAVE = 'transportadoras'.freeze
  MODELO = Autonomia::FerramentasProntas::Bases::Transportador
  HOST = 'dados.antt.gov.br'.freeze
  HOSTS = [HOST].freeze
  FREQUENCIA = :mensal
  MINIMO = 500_000
  CATALOGO = "https://#{HOST}/api/3/action/package_show?id=rntrc".freeze
  NOME_DO_ARQUIVO = 'transportadores_rntrc_'.freeze
  MAX_BYTES = 400.megabytes
  PRAZO = 1_800
  COLUNAS = %w[rntrc cnpj nome categoria situacao municipio uf cadastrado_em situacao_desde equiparado].freeze
  CABECALHO = %w[nome_transportador numero_rntrc data_primeiro_cadastro situacao_rntrc cpfcnpjtransportador
                 categoria_transportador municipio uf equiparado data_situacao_rntrc].freeze
  CATEGORIAS = { 'ETC' => 'empresa', 'CTC' => 'cooperativa', 'TAC' => 'autônomo' }.freeze
  COM_CNPJ = %w[ETC CTC].freeze
  DIGITOS_DO_RNTRC = 9
  ASPAS = "' ".freeze

  class << self
    def baixar(download)
      { rntrc: download.baixar(endereco_do_mes(download), max_bytes: MAX_BYTES, prazo: PRAZO) }
    end

    # O CSV mais novo do conjunto, pela data de publicação. Recurso de outro host ou fora do padrão do nome: ignorado.
    def endereco_do_mes(download)
      recursos = Array(download.json(CATALOGO).dig('result', 'resources'))
      arquivos = recursos.select { |recurso| recurso.is_a?(Hash) && arquivo_do_mes?(recurso['url']) }
      raise Autonomia::FerramentasProntas::Bases::Falha, 'formato_mudou' if arquivos.empty?

      arquivos.max_by { |recurso| [recurso['last_modified'].to_s, recurso['created'].to_s] }['url']
    end

    def arquivo_do_mes?(url)
      destino = URI.parse(url.to_s)
      destino.is_a?(URI::HTTPS) && destino.host == HOST && File.basename(destino.path).start_with?(NOME_DO_ARQUIVO) &&
        destino.path.end_with?('.csv')
    rescue URI::InvalidURIError
      false
    end

    def linhas(arquivos)
      rntrc = csv(arquivos.fetch(:rntrc), colunas: CABECALHO, codificacao: 'ISO-8859-1:UTF-8')
      Enumerator.new do |saida|
        rntrc.each { |linha| saida << transportador(linha) }
      end
    end

    def transportador(linha)
      numero = rntrc(linha['numero_rntrc'])
      sigla = linha['categoria_transportador'].to_s.strip.upcase
      return if numero.nil? || sigla.empty?

      [numero, *identidade(linha, sigla), CATEGORIAS.fetch(sigla, sigla.downcase), linha['situacao_rntrc'].to_s.strip.downcase,
       texto(linha['municipio']), texto(linha['uf']), data(linha['data_primeiro_cadastro']), data(linha['data_situacao_rntrc']),
       equiparado(linha['equiparado'])]
    end

    # [CNPJ, nome] da empresa e da cooperativa com CNPJ válido; de qualquer outro, nada.
    def identidade(linha, sigla)
      cnpj = Autonomia::FerramentasProntas::Parametro.cnpj(linha['cpfcnpjtransportador']) if COM_CNPJ.include?(sigla)
      return [nil, nil] if cnpj.nil?

      [cnpj, sem_cpf(nome(linha['nome_transportador']))]
    end

    # "50085788" e "050085788" -> "050085788".
    def rntrc(valor)
      numero = digitos(valor)
      numero.rjust(DIGITOS_DO_RNTRC, '0') if numero && numero.length <= DIGITOS_DO_RNTRC
    end

    # "'' DPS LOGISTICA LTDA ''" -> "DPS LOGISTICA LTDA".
    def nome(valor)
      texto = valor.to_s.squish
      texto = texto[1..] while texto.start_with?(*ASPAS.chars)
      texto = texto[..-2] while texto.end_with?(*ASPAS.chars)
      texto.presence
    end

    def equiparado(valor)
      case Autonomia::FerramentasProntas::Lista.comparavel(valor)
      when 'sim' then true
      when 'nao' then false
      end
    end
  end
end
