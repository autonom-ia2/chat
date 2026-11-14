require 'csv'

# Os exemplos de uma planilha de "Trazer minha lista" (#2896): as primeiras pessoas que vão entrar, lidas na hora e só
# para a resposta da tela. Nada daqui é gravado nem vai para o log.
#
# Vêm do arquivo conferido (`normalized_csv`, 30 dias), que só tem as linhas aprovadas. Só o começo do arquivo é baixado,
# e ele é lido por registro: a célula com quebra de linha conta como uma pessoa só. Sem o arquivo não há exemplo. As
# linhas com problema têm arquivo próprio (ContactImports::Trazer::LinhasComProblema).
class Relacionamentos::Trazer::LinhasDaPlanilha
  EXEMPLOS = 3
  COMECO_DO_ARQUIVO = 16.kilobytes
  ASPA_DA_PROTECAO = "'".freeze
  FIM_DE_LINHA = "\n".freeze

  def initialize(importacao)
    @importacao = importacao
  end

  def exemplos
    return [] unless @importacao.normalized_csv.attached?

    primeiros_registros.map do |linha|
      # O arquivo conferido protege a célula que começa com "+" com uma aspa (CsvSanitizer.safe_cell).
      { linha: linha['row_number'].to_i, nome: linha['name'].to_s, telefone: linha['phone_number'].to_s.delete_prefix(ASPA_DA_PROTECAO),
        email: linha['email'].to_s, empresa: linha['company_name'].to_s }
    end
  end

  private

  # Os primeiros registros que vieram inteiros no trecho lido. O leitor para no último exemplo; se o trecho acaba no
  # meio de uma célula entre aspas, ficam os registros lidos até ali, e o log leva o id e a classe do erro (nunca a
  # mensagem, que cita o trecho).
  def primeiros_registros
    registros = []
    CSV.new(comeco_do_conferido, headers: true).each do |linha|
      registros << linha
      break if registros.size == EXEMPLOS
    end
    registros
  rescue CSV::MalformedCSVError => e
    Rails.logger.warn("[Relacionamentos::Trazer::LinhasDaPlanilha] import_id=#{@importacao.id} #{e.class}")
    registros
  end

  # O começo do arquivo, até a última linha que veio inteira: o corte do trecho baixado pode cair no meio de uma.
  def comeco_do_conferido
    blob = @importacao.normalized_csv.blob
    trecho = blob.download_chunk(0...COMECO_DO_ARQUIVO).b
    trecho = trecho[0..trecho.rindex(FIM_DE_LINHA)] if blob.byte_size > trecho.bytesize && trecho.include?(FIM_DE_LINHA)
    trecho.force_encoding(Encoding::UTF_8)
  end
end
