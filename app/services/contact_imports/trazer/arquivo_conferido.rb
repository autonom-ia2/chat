require 'csv'
require 'stringio'

# "Trazer minha lista" (#2896): o arquivo conferido da importação (`normalized_csv`, o mesmo que o importador lê), do
# jeito que o fechamento da conferência mexe nele (ContactImports::Trazer::FecharConferencia, num job). Nenhuma rota
# da tela abre este arquivo inteiro: a conferência lê os consertos do arquivo próprio deles
# (ContactImports::Trazer::Consertos).
#
# As colunas e a proteção das células são as do validador (CampaignImports::AudienceValidator, CsvSanitizer.safe_cell).
class ContactImports::Trazer::ArquivoConferido
  CABECALHO = CampaignImports::AudienceValidator::AUDIENCE_NORMALIZED_HEADERS
  TIPO = 'text/csv'.freeze

  # A linha que a pessoa consertou, com as células protegidas como as que o validador grava.
  def self.protegida(conferida)
    CABECALHO.index_with { |coluna| CampaignImports::CsvSanitizer.safe_cell(conferida[coluna]) }
  end

  def initialize(importacao)
    @importacao = importacao
  end

  def existe?
    anexo.attached?
  end

  # { número => linha } de tudo que o arquivo tem, na ordem dos números. As células vêm como foram gravadas, já
  # protegidas.
  def linhas
    achadas = {}
    anexo.blob.open do |arquivo|
      CSV.foreach(arquivo.path, headers: true, encoding: Encoding::UTF_8.name) { |linha| achadas[linha['row_number'].to_i] = linha.to_h }
    end
    achadas.sort.to_h
  end

  # Troca o arquivo por um só com estas linhas ({ número => linha }, como `linhas` devolve).
  def regravar(linhas)
    texto = CSV.generate { |csv| [CABECALHO, *linhas.values.map { |linha| linha.values_at(*CABECALHO) }].each { |celulas| csv << celulas } }
    anexo.attach(io: StringIO.new(texto), filename: anexo.blob.filename.to_s, content_type: TIPO)
  end

  private

  def anexo
    @importacao.normalized_csv
  end
end
