require 'json'
require 'stringio'

# "Trazer minha lista" (#2896): o arquivo dos consertos que a pessoa fez nas linhas com problema. É o ÚNICO lugar onde o
# valor que ela digitou fica (nada disso vai para options, validation_summary, linhas ou log), e é pequeno: uma linha
# por linha consertada, nunca a planilha.
#
# Uma linha por linha da planilha, em JSON:
#   {"linha":14,"campo":"telefone","valores":{"phone":"11 98765-0004"},"conferida":{"row_number":14,"name":"…",…}}
# - `valores`: o que a pessoa digitou, por alvo (phone, email, name);
# - `campo`: o último campo consertado (telefone, email, nome, contato ou ficar_com);
# - `outra`: na linha repetida que a pessoa escolheu manter, a linha que sai no lugar dela;
# - `conferida`: a linha como vai entrar (as colunas do arquivo conferido), quando o conserto resolveu a linha inteira;
# - `sobrou`: o motivo que ainda falta resolver, quando não resolveu.
#
# O arquivo é trocado inteiro a cada conserto. A leitura da planilha não o apaga: quando ela termina, os consertos que
# ainda valem são conferidos de novo e regravados (ContactImports::Trazer::ConsertosDaLeitura). Some no prazo da planilha
# original (ContactImports::Trazer::AnexosVencidos).
#
# - `colunas`: a coluna (índice) de cada alvo consertado, na leitura em que o conserto foi feito.
#
# Cada objeto baixa o arquivo uma vez e guarda o que leu, e o que grava passa a ser o que ele lê: quem atende um pedido
# cria UM e o passa adiante. No pior caso (50 mil linhas consertadas) o arquivo tem cerca de 25 MB; na prática tem o
# tamanho do que a pessoa consertou à mão. O arquivo velho só é apagado do armazenamento depois que a transação termina
# (ContactImports::Trazer::ApagarAnexo).
class ContactImports::Trazer::Consertos
  NOME = 'consertos.jsonl'.freeze
  TIPO = 'application/x-ndjson'.freeze

  def initialize(importacao)
    @importacao = importacao
  end

  # { número da linha => o que o arquivo guarda dela }. Sem arquivo, nenhum conserto.
  def ler
    @lidos = do_arquivo if @lidos.nil?
    @lidos
  end

  # consertos: { número da linha => o que guardar dela }. Sem nenhum, o arquivo deixa de existir.
  def gravar(consertos)
    @lidos = consertos
    return apagar if consertos.empty?

    texto = consertos.sort.map { |_numero, feito| JSON.generate(feito) }.join("\n")
    anexo.attach(io: StringIO.new(texto), filename: NOME, content_type: TIPO)
  end

  private

  def do_arquivo
    return {} unless anexo.attached?

    anexo.download.force_encoding(Encoding::UTF_8).each_line.to_h do |texto|
      feito = JSON.parse(texto)
      [feito['linha'], feito]
    end
  rescue JSON::ParserError
    raise ContactImports::Trazer::ArquivoIlegivel, NOME, cause: nil
  end

  def apagar
    ContactImports::Trazer::ApagarAnexo.call(anexo)
  end

  def anexo
    @importacao.public_send(Relacionamentos::Trazer::ArquivoDeProblemas::CONSERTOS)
  end
end
