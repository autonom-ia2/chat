# Comparação de valor com a prova (A9 da 2ª revisão), sem regex: minúsculas, sem acento, só letras a-z e dígitos. O CPF
# "123.456.789-00" vira "12345678900" e está contido em "meu cpf e 123 456 789 00" normalizado. É comparação estrutural
# de igualdade (contido), não interpretação do que a pessoa quis dizer.
module Crm::Memoria::Normal
  module_function

  def chave(texto)
    Autonomia::Agents::Operate::TextoSemDisfarce.normalizado(texto.to_s).unicode_normalize(:nfkd).downcase.delete('^a-z0-9')
  end

  # Valor curto ("SP", "2002") se confere por palavra inteira (ou palavras vizinhas juntas: "12 34"), nunca dentro de
  # outra ("2002" não está em "12002"). Do tamanho de um documento para cima, basta estar contido no texto normalizado
  # (o CPF "123.456.789-09" em "cpf:12345678909").
  TAMANHO_DE_SUBSTRING = 5
  JANELA_DE_PALAVRAS = 6

  def contido?(valor, textos)
    alvo = chave(valor)
    return false if alvo.empty?

    Array(textos).any? { |texto| alvo.length >= TAMANHO_DE_SUBSTRING ? chave(texto).include?(alvo) : em_palavras?(alvo, texto) }
  end

  def em_palavras?(alvo, texto)
    palavras = texto.to_s.split.map { |palavra| chave(palavra) }.reject(&:empty?)
    palavras.each_index.any? do |inicio|
      (1..JANELA_DE_PALAVRAS).any? { |tamanho| palavras[inicio, tamanho].join == alvo }
    end
  end

  # O texto de uma mensagem como prova: o conteúdo e o que se tirou dos anexos (transcrição do áudio, legenda da imagem).
  def texto_da_mensagem(message)
    partes = [message.content.to_s]
    message.attachments.each do |anexo|
      meta = anexo.meta.to_h
      partes << meta['transcribed_text'].to_s << meta['ai_caption'].to_s
    end
    partes.compact_blank.join(' ').squish
  end

  # O valor numa linha só, sem caracteres invisíveis, no tamanho máximo do fato.
  def linha(texto)
    Autonomia::Agents::Operate::TextoSemDisfarce.normalizado(texto.to_s).squish.first(Crm::MemoriaFato::VALOR_MAXIMO)
  end
end
