# PLACAS SOLARES (#2858, F5): a geração distribuída registrada na ANEEL (micro e minigeração: placas solares, quase
# todas), SOMADA por CEP, município, tipo e classe de consumo. Mensal.
#   - um ZIP (`empreendimento-geracao-distribuida.zip`, ~110 MB) com um CSV de ~1,5 GB e ~4,7 milhões de linhas,
#     separado por ";", em UTF-8. O ZIP fica no disco e o CSV é lido por streaming de dentro dele, com teto sobre o
#     tamanho aberto (`MAX_ABERTO`, contra bomba de zip): o declarado E o que se lê de verdade;
#   - a soma fica em memória (~160 mil chaves em 11/2026; teto `MAX_CHAVES`) e vai à tabela só depois. Só ela é
#     gravada: nenhum titular (nome ou CPF tarjado), nenhum código de empreendimento, nenhuma coordenada.
#     "Tem placa solar no CEP X?" responde com a contagem.
class Autonomia::FerramentasProntas::Bases::GeracaoSolar < Autonomia::FerramentasProntas::Bases::Importador
  CHAVE = 'geracao_solar'.freeze
  MODELO = Autonomia::FerramentasProntas::Bases::GeracaoDistribuida
  HOSTS = %w[dadosabertos.aneel.gov.br].freeze
  FREQUENCIA = :mensal
  MINIMO = 50_000
  ARQUIVO = 'https://dadosabertos.aneel.gov.br/dataset/5e0fafd2-21b9-4d5b-b622-40438d40aba2/resource/' \
            'b1bd71e7-d0ad-4214-9053-cbd58e9564a7/download/empreendimento-geracao-distribuida.zip'.freeze
  MAX_BYTES = 400.megabytes
  MAX_ABERTO = 4.gigabytes
  # Mais chaves que isso na soma é arquivo que não é o da ANEEL (e não deixa a memória crescer sem fim).
  MAX_CHAVES = 1_000_000
  PRAZO = 1_800
  COLUNAS = %w[cep codigo_municipio uf tipo classe quantidade potencia_kw].freeze
  CABECALHO = %w[SigUF CodMunicipioIbge CodCEP DscClasseConsumo SigTipoGeracao MdaPotenciaInstaladaKW].freeze
  TIPOS = { 'UFV' => 'solar', 'EOL' => 'eólica', 'UTE' => 'termelétrica', 'CGH' => 'hidrelétrica', 'PCH' => 'hidrelétrica',
            'UHE' => 'hidrelétrica' }.freeze
  OUTRA = 'outra'.freeze

  class << self
    def baixar(download)
      { zip: download.baixar(ARQUIVO, max_bytes: MAX_BYTES, prazo: PRAZO) }
    end

    # Soma primeiro e entrega a soma: o COPY recebe ~220 mil linhas, não 4,7 milhões.
    def linhas(arquivos)
      somas = somar(arquivos.fetch(:zip))
      somas.lazy.map { |chave, (quantidade, potencia)| [*chave, quantidade, potencia.round(2)] }
    end

    def somar(zip)
      somas = Hash.new { |hash, chave| hash[chave] = [0, 0.0] }
      com_csv_aberto(zip) do |io|
        csv(io, colunas: CABECALHO).each do |linha|
          chave = chave_da_soma(linha)
          next if chave.nil?

          soma = somas[chave]
          raise Autonomia::FerramentasProntas::Bases::Falha, 'formato_mudou' if somas.size > MAX_CHAVES

          soma[0] += 1
          soma[1] += potencia(linha['MdaPotenciaInstaladaKW'])
        end
      end
      somas
    end

    def chave_da_soma(linha)
      municipio = digitos(linha['CodMunicipioIbge'])
      cep = digitos(linha['CodCEP'])
      return if municipio.nil? && cep.nil?

      [cep&.length == 8 ? cep : nil, municipio, repetido(linha['SigUF']), TIPOS.fetch(linha['SigTipoGeracao'].to_s.strip, OUTRA),
       repetido(linha['DscClasseConsumo'])]
    end

    # A UF e a classe se repetem em milhões de linhas: uma cópia só de cada texto na memória.
    def repetido(valor)
      limpo = texto(valor)
      limpo && -limpo
    end

    # "32,50" -> 32.5
    def potencia(valor)
      Float(valor.to_s.strip.tr(',', '.'), exception: false) || 0.0
    end

    # O único CSV do ZIP, lido por streaming direto do pacote (nada de 1,5 GB aberto em disco). Contra bomba de zip, o
    # teto `MAX_ABERTO` vale duas vezes: para o tamanho que o ZIP declara (recusa antes de ler) e para os bytes que a
    # leitura de fato entrega (`LeituraComTeto`): o rubyzip não confere o declarado ao descomprimir, e o ZIP pode mentir.
    def com_csv_aberto(zip)
      Zip::File.open(zip.path) do |pacote|
        entrada = pacote.entries.find { |item| item.file? && item.name.downcase.end_with?('.csv') }
        raise Autonomia::FerramentasProntas::Bases::Falha, 'formato_mudou' if entrada.nil?
        raise Autonomia::FerramentasProntas::Bases::Falha, 'arquivo_grande_demais' if entrada.size > MAX_ABERTO

        entrada.get_input_stream { |io| yield Autonomia::FerramentasProntas::Bases::LeituraComTeto.new(io, MAX_ABERTO) }
      end
    rescue Zip::Error
      raise Autonomia::FerramentasProntas::Bases::Falha, 'formato_mudou'
    end
  end
end
