# "Trazer minha lista" (#2896): o que a pessoa já consertou e deixou de fora continua valendo quando a planilha é lida
# de novo (ela trocou uma coluna, por exemplo). Os consertos vivem num arquivo próprio (ContactImports::Trazer::Consertos)
# que a leitura não apaga: a leitura que falha não perde nada, e a próxima que dá certo os confere de novo.
#
# - `reaplicar` confere cada conserto contra a linha como a leitura nova a viu, com os leitores desta leitura
#   (ContactImports::Trazer::Conserto). O conserto da linha que sumiu, que deixou de ter problema ou cujo valor não vale
#   mais é esquecido, e a linha volta a ser o que a leitura nova diz. O conserto vale para a coluna em que foi feito
#   (`colunas`, o índice de cada alvo consertado): se a leitura nova põe outra coluna naquele alvo, ele é esquecido.
# - `gravar` troca o arquivo pelos consertos que continuam valendo.
# - A marca de "deixada de fora" fica só na linha que continua com problema: a linha que a leitura nova aprovou é
#   pessoa boa e entra (decisão do dono).
# - A leitura que dá certo joga fora a cópia que servia para desfazer a mudança (ContactImports::Trazer::DesfazerMudanca).
class ContactImports::Trazer::ConsertosDaLeitura
  def initialize(importacao)
    @importacao = importacao
    @arquivo = ContactImports::Trazer::Consertos.new(importacao)
    @mantidos = {}
  end

  # linhas: as do validador, depois de conferidas; conserto: ContactImports::Trazer::Conserto desta leitura.
  def reaplicar(linhas, conserto)
    por_numero = linhas.index_by { |linha| linha[:row_number] }
    @arquivo.ler.each do |numero, feito|
      linha = por_numero[numero]
      refeito = linha && linha[:errors].present? && refazer(linha, feito, conserto)
      @mantidos[numero] = refeito if refeito
    end
  end

  def gravar
    @arquivo.gravar(@mantidos)
  end

  # As opções da importação com as marcas que continuam valendo depois desta leitura.
  def opcoes_depois_da_leitura(linhas)
    conferencia = ContactImports::Trazer::Conferencia.new(@importacao)
    opcoes = @importacao.options.to_h
    marcas = opcoes[ContactImports::Trazer::Conferencia::CHAVE].to_h.except(ContactImports::Trazer::DesfazerMudanca::CHAVE)
    return opcoes.merge(ContactImports::Trazer::Conferencia::CHAVE => marcas) if conferencia.deixadas.empty?

    com_problema = linhas.select { |linha| linha[:errors].present? }.pluck(:row_number)
    opcoes.merge(ContactImports::Trazer::Conferencia::CHAVE => marcas.merge('deixadas' => conferencia.deixadas & com_problema))
  end

  private

  # A escolha de uma linha repetida só continua valendo se a linha ainda é repetida da mesma outra; e o conserto de
  # um valor não vale para a linha que a leitura nova passou a ver como repetida.
  def refazer(linha, feito, conserto)
    return unless linha.dig(:outra, :row_number) == feito['outra']
    return if feito['colunas'].to_h.any? { |alvo, indice| conserto.alvos[alvo] != indice }

    resultado = conserto.reconferir(linha[:row_number], linha[:celulas], feito['valores'].to_h)
    return if resultado.motivo

    feito.slice('linha', 'campo', 'outra', 'colunas')
         .merge('valores' => resultado.valores, 'conferida' => resultado.conferida, 'sobrou' => resultado.sobrou).compact
  end
end
