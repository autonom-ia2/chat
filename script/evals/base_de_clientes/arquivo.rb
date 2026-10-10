require 'csv'
require 'caxlsx'

# Escreve o arquivo de um caso (#1246) como uma pessoa o exportaria: CSV com o separador e a
# codificação do caso, ou XLSX de verdade (caxlsx), com número gravado como número.
module BaseDeClientesEval::Arquivo
  module_function

  def bytes(caso)
    caso.formato == 'xlsx' ? xlsx(caso) : csv(caso)
  end

  def nome(caso)
    "#{caso.id}.#{caso.formato}"
  end

  def csv(caso)
    opcoes = caso.opcoes
    texto = CSV.generate(col_sep: opcoes.fetch(:col_sep, ','), force_quotes: opcoes.fetch(:force_quotes, false)) do |saida|
      caso.abas.fetch(caso.aba_alvo).linhas.each { |linha| saida << linha.map(&:to_s) }
    end
    codificacao = opcoes[:encoding]
    codificacao ? texto.encode(codificacao, invalid: :replace, undef: :replace, replace: '?').b : texto.b
  end

  def xlsx(caso)
    pacote = Axlsx::Package.new
    caso.abas.each do |aba|
      pacote.workbook.add_worksheet(name: aba.nome) do |folha|
        aba.linhas.each { |linha| folha.add_row(linha, types: linha.map { |valor| tipo(valor) }) }
      end
    end
    pacote.to_stream.read.b
  end

  def tipo(valor)
    case valor
    when Integer then :integer
    when Float then :float
    else :string
    end
  end
end
