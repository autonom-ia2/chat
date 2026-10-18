# O corte do BLOCO CITADO de um e-mail recebido (#1807), para Crm::Email::Autoria.texto_novo. Quem decide o que é
# citação, marcador ("On ... wrote:") ou cabeçalho é o EmailReplyTrimmer (identify_line_content); aqui só se junta a
# classificação dele linha a linha. Diferente do `EmailReplyTrimmer.trim`, a assinatura fica.
module Crm::Email::BlocoCitado
  # Tipos de linha do EmailReplyTrimmer: o marcador e a linha citada abrem o bloco citado; vazia e cabeçalho seguem nele.
  CITACAO = [EmailReplyTrimmer::EMBEDDED, EmailReplyTrimmer::QUOTE].freeze
  DENTRO_DA_CITACAO = [EmailReplyTrimmer::EMPTY, EmailReplyTrimmer::EMAIL_HEADER].freeze
  CABECALHOS_DO_ENCAMINHADO = 3

  # Linha a linha, pela classificação do EmailReplyTrimmer: some o marcador da citação ("On ... wrote:"), as linhas
  # citadas (">") e o que fica entre elas. Some tudo a partir do e-mail anterior colado SEM ">" (#inicio_do_historico).
  # Texto, separador "--" e assinatura ficam. Texto com codificação inválida: '' (quem chama cai no texto inteiro).
  def self.sem(conteudo)
    return '' unless conteudo.valid_encoding?

    linhas = conteudo.dup.tap { |texto| EmailReplyTrimmer.preprocess!(texto) }.split("\n")
    tipos = marcadores_de_verdade(linhas, linhas.map { |linha| EmailReplyTrimmer.identify_line_content(linha) })
    fim = inicio_do_historico(linhas, tipos) || linhas.size
    fora_da_citacao(linhas.first(fim), tipos).join("\n").strip
  end

  # As linhas que não estão num bloco citado: o bloco abre no marcador ou na linha citada e segue nas vazias e nos
  # cabeçalhos; a próxima linha de texto (ou separador, assinatura) o fecha.
  def self.fora_da_citacao(linhas, tipos)
    dentro = false
    linhas.each_with_index.filter_map do |linha, indice|
      dentro = true if CITACAO.include?(tipos[indice])
      next if dentro && (CITACAO + DENTRO_DA_CITACAO).include?(tipos[indice])

      dentro = false
      linha
    end
  end

  # Onde começa o e-mail anterior colado sem ">", ou nil: (a) o marcador ("On ... wrote:") sem linha citada depois;
  # (b) 3 cabeçalhos seguidos ("De:/Enviado:/Para:") logo depois de um separador ("____") ou cujo primeiro
  # traz um endereço ("De: João <joao@...>"). Sem essa exigência, "De: Curitiba / Para: Recife / Data: 10/10" escrito
  # pelo cliente sumiria.
  def self.inicio_do_historico(linhas, tipos)
    cheias = tipos.each_index.reject { |indice| tipos[indice] == EmailReplyTrimmer::EMPTY }
    cheias.each_with_index do |indice, posicao|
      seguinte = tipos[cheias[posicao + 1]] if cheias[posicao + 1]
      return indice if tipos[indice] == EmailReplyTrimmer::EMBEDDED && CITACAO.exclude?(seguinte)

      inicio = inicio_dos_cabecalhos(linhas, tipos, cheias, posicao)
      return inicio if inicio
    end
    nil
  end

  def self.inicio_dos_cabecalhos(linhas, tipos, cheias, posicao)
    return unless bloco_de_cabecalhos?(tipos, cheias, posicao)

    anterior = cheias[posicao - 1] if posicao.positive?
    return anterior if anterior && tipos[anterior] == EmailReplyTrimmer::DELIMITER

    cheias[posicao] if linhas[cheias[posicao]].include?('@')
  end

  # O marcador ("On ... wrote:") só vale como marcador se traz um endereço ("<x@y>") ou se a próxima linha cheia é
  # citada; senão é texto ("On Monday my wife said:" escrito pelo cliente, que cortaria o resto da mensagem).
  def self.marcadores_de_verdade(linhas, tipos)
    cheias = tipos.each_index.reject { |indice| tipos[indice] == EmailReplyTrimmer::EMPTY }
    tipos.each_with_index.map do |tipo, indice|
      next tipo unless tipo == EmailReplyTrimmer::EMBEDDED

      seguinte = cheias.find { |outro| outro > indice }
      marcador?(linhas[indice], seguinte && tipos[seguinte]) ? tipo : EmailReplyTrimmer::TEXT
    end
  end

  def self.marcador?(linha, tipo_seguinte)
    linha.include?('@') || tipo_seguinte == EmailReplyTrimmer::QUOTE
  end

  def self.bloco_de_cabecalhos?(tipos, cheias, posicao)
    bloco = cheias[posicao, CABECALHOS_DO_ENCAMINHADO]
    bloco.size == CABECALHOS_DO_ENCAMINHADO && bloco.all? { |indice| tipos[indice] == EmailReplyTrimmer::EMAIL_HEADER }
  end
end
