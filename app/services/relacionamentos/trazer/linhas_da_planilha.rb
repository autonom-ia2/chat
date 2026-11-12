require 'csv'

# Os valores inteiros de uma planilha de "Trazer minha lista" (#2896), lidos na hora e só para a resposta da tela: nada
# daqui é gravado nem vai para o log.
#
# - Os exemplos (as primeiras pessoas que vão entrar) vêm do arquivo conferido (`normalized_csv`, 30 dias), que só tem as
#   linhas aprovadas. Só o começo do arquivo é baixado. Sem o arquivo não há exemplo.
# - As células das linhas com problema vêm da planilha original (`original_file`, 7 dias), aberta só quando alguém pede
#   linhas, e só as pedidas ficam na memória. No CSV a leitura corre em fluxo e para na maior linha pedida. No XLSX o
#   leitor de planilhas monta a aba inteira; as linhas que não foram pedidas são soltas em seguida.
#   Depois que a planilha é apagada, `inteira?` responde não e a tela mostra as máscaras guardadas na linha.
class Relacionamentos::Trazer::LinhasDaPlanilha
  EXEMPLOS = 3
  COMECO_DO_ARQUIVO = 16.kilobytes
  ASPA_DA_PROTECAO = "'".freeze
  XLSX = 'xlsx'.freeze
  VIRGULA = ','.freeze
  MARCAS_DE_UTF16 = { "\xFF\xFE".b => Encoding::UTF_16LE, "\xFE\xFF".b => Encoding::UTF_16BE }.freeze
  MARCA_DE_UTF8 = "\xEF\xBB\xBF".b.freeze
  ILEGIVEL = "\uFFFD".freeze

  def initialize(importacao)
    @importacao = importacao
    @resolucao = importacao.schema_resolution.to_h
  end

  def inteira?
    @importacao.original_file.attached?
  end

  def exemplos
    return [] unless @importacao.normalized_csv.attached?

    CSV.parse(comeco_do_conferido, headers: true).map do |linha|
      # O arquivo conferido protege a célula que começa com "+" com uma aspa (CsvSanitizer.safe_cell).
      { nome: linha['name'].to_s, telefone: linha['phone_number'].to_s.delete_prefix(ASPA_DA_PROTECAO), email: linha['email'].to_s,
        empresa: linha['company_name'].to_s, cliente: false }
    end
  end

  # { número da linha => [células] } das linhas pedidas da planilha original, pelo número que a leitura gravou.
  # O bloco recebe o que foi achado e pode pedir mais linhas da mesma planilha (a outra linha de uma repetida).
  def ler(numeros)
    return {} unless inteira? && numeros.any?

    achadas = buscar(numeros)
    mais = block_given? ? Array(yield(achadas)).compact - achadas.keys : []
    mais.empty? ? achadas : achadas.merge(buscar(mais))
  ensure
    @texto_do_csv = @linhas_do_xlsx = nil
  end

  private

  # O cabeçalho e as primeiras linhas, inteiras: o corte do trecho baixado só pode cair depois delas.
  def comeco_do_conferido
    trecho = @importacao.normalized_csv.blob.download_chunk(0...COMECO_DO_ARQUIVO)
    trecho.b.lines.first(EXEMPLOS + 1).join.force_encoding(Encoding::UTF_8)
  end

  def buscar(numeros)
    pedidas = numeros.to_set
    @resolucao['format'] == XLSX ? buscar_no_xlsx(pedidas) : buscar_no_csv(pedidas)
  end

  # O número da linha é a posição dela no arquivo, a partir de 1, como em CampaignImports::Parser.
  def buscar_no_csv(pedidas)
    ultima = pedidas.max
    achadas = {}
    CSV.new(texto_do_csv, col_sep: @resolucao['delimiter'].presence || VIRGULA, liberal_parsing: true).each.with_index(1) do |celulas, numero|
      break if numero > ultima

      achadas[numero] = Array(celulas).map(&:to_s) if pedidas.include?(numero)
    end
    achadas
  end

  def buscar_no_xlsx(pedidas)
    linhas_do_xlsx.each_with_object({}) { |linha, achadas| achadas[linha.number] = linha.values if pedidas.include?(linha.number) }
  end

  # A planilha fica aberta só durante um `ler`: quem pede a outra linha de uma repetida não a baixa duas vezes.
  def linhas_do_xlsx
    @linhas_do_xlsx ||= CampaignImports::XlsxReader.new(@importacao.original_file.download).sheets.fetch(@resolucao['table_index'].to_i).rows
  end

  # O mesmo texto que a leitura viu (CampaignImports::Parser, que não expõe a conversão): UTF-16 pela marca do começo,
  # UTF-8 com ou sem marca e, se os bytes não são UTF-8, Windows-1252.
  def texto_do_csv
    @texto_do_csv ||= begin
      bruto = @importacao.original_file.download.b
      marca, utf16 = MARCAS_DE_UTF16.find { |inicio, _encoding| bruto.start_with?(inicio) }
      utf16 ? convertido(bruto.delete_prefix(marca), utf16) : texto_de_um_byte(bruto.delete_prefix(MARCA_DE_UTF8))
    end
  end

  def texto_de_um_byte(bruto)
    utf8 = bruto.dup.force_encoding(Encoding::UTF_8)
    utf8.valid_encoding? ? utf8 : convertido(bruto, Encoding::Windows_1252)
  end

  def convertido(bruto, encoding)
    bruto.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: ILEGIVEL)
  end
end
