require 'json'
require 'stringio'

# "Trazer minha lista" (#2896): o arquivo das linhas da planilha que precisam da pessoa.
#
# A leitura da planilha (ContactImports::Trazer::Validador) grava aqui, a cada passada, só as linhas que deram problema:
# o número da linha e as células dos quatro alvos (nome, telefone já com o DDD, e-mail e empresa) como vieram. Nenhuma
# outra coluna entra, nem a que a pessoa marcou "não guardar". A linha repetida leva junto as células da outra linha da
# mesma pessoa. A tela lê daqui os valores inteiros e não abre a planilha original, que num XLSX grande custa segundos e
# centenas de MB.
#
# Uma linha por linha da planilha, em JSON, na ordem dos números:
#   {"linha":143,"celulas":{"name":"…","phone":"…","email":"…","company":"…"},"outra":{"linha":88,"celulas":{…}}}
# O arquivo é trocado inteiro a cada leitura e some no prazo da planilha original, contado da criação da importação
# (ContactImports::Trazer::AnexosVencidos). Nada daqui vai para o log. Se um dia virar arquivo para baixar, as células
# têm de passar por CampaignImports::CsvSanitizer.
#
# Cada objeto abre o arquivo o mínimo possível e guarda o que leu: quem atende um pedido cria UM e o passa adiante. A
# linha pedida de novo não abre o arquivo outra vez. `repetidas_de` é o único caso que lê o arquivo inteiro (no pior
# caso, 50 mil linhas com problema: cerca de 10 MB, lidos linha a linha).
#
# O arquivo velho só é apagado do armazenamento depois que a transação termina (ContactImports::Trazer::ApagarAnexo): a
# leitura que quebra no meio e volta atrás não fica com o anexo apontando para um arquivo que já sumiu, e nenhum
# arquivo fica sem dono.
class ContactImports::Trazer::LinhasComProblema
  NOME = 'linhas_com_problema.jsonl'.freeze
  TIPO = 'application/x-ndjson'.freeze

  def initialize(importacao)
    @importacao = importacao
    esquecer
  end

  def existe?
    anexo.attached?
  end

  # linhas: as do validador que têm erro ({ row_number:, celulas:, outra: a linha que ficou no lugar dela ou nil }).
  def gravar(linhas)
    return apagar if linhas.empty?

    esquecer
    texto = linhas.sort_by { |linha| linha[:row_number] }.map { |linha| JSON.generate(entrada(linha)) }.join("\n")
    anexo.attach(io: StringIO.new(texto), filename: NOME, content_type: TIPO)
  end

  def apagar
    esquecer
    ContactImports::Trazer::ApagarAnexo.call(anexo)
  end

  # { número da linha => { 'linha' =>, 'celulas' => {...}, 'outra' => { 'linha' =>, 'celulas' => {...} } } } das linhas
  # pedidas. O arquivo é lido linha a linha e a leitura para quando todas as pedidas foram achadas.
  def ler(numeros)
    pedidas = numeros.to_set
    return {} if pedidas.empty? || !existe?

    buscar(pedidas - @lidas.keys) unless @inteiro
    @lidas.slice(*pedidas).compact
  end

  # Os números das linhas repetidas desta linha (as que a leitura guardou com ela como `outra`). Lê o arquivo inteiro.
  def repetidas_de(numero)
    ler_tudo
    @lidas.values.compact.select { |entrada| entrada.dig('outra', 'linha') == numero }.pluck('linha')
  end

  # Lê o arquivo inteiro de uma vez, para quem sabe que vai precisar do grupo de uma linha repetida.
  def ler_tudo
    return if @inteiro || !existe?

    cada_entrada { |entrada| @lidas[entrada['linha']] = entrada }
    @inteiro = true
  end

  private

  def esquecer
    @lidas = {}
    @inteiro = false
  end

  # A linha que o arquivo não tem fica lembrada como nil: pedir de novo não abre o arquivo.
  def buscar(faltam)
    return if faltam.empty?

    cada_entrada do |entrada|
      @lidas[entrada['linha']] = entrada if faltam.delete?(entrada['linha'])
      break if faltam.empty?
    end
    faltam.each { |numero| @lidas[numero] = nil }
  end

  def cada_entrada
    anexo.blob.open do |arquivo|
      arquivo.each_line { |texto| yield JSON.parse(texto.force_encoding(Encoding::UTF_8)) }
    end
  rescue JSON::ParserError
    raise ContactImports::Trazer::ArquivoIlegivel, NOME, cause: nil
  end

  def anexo
    @importacao.public_send(Relacionamentos::Trazer::ArquivoDeProblemas::ANEXO)
  end

  def entrada(linha)
    outra = linha[:outra]
    base = { 'linha' => linha[:row_number], 'celulas' => linha[:celulas] }
    outra ? base.merge('outra' => { 'linha' => outra[:row_number], 'celulas' => outra[:celulas] }) : base
  end
end
