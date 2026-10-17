# Comparação de valor com a prova (A9 da 2ª revisão), sem regex: minúsculas, sem acento, só letras a-z e dígitos. O CPF
# "123.456.789-00" vira "12345678900" e está contido em "meu cpf e 123 456 789 00" normalizado. É comparação estrutural
# de igualdade (contido), não interpretação do que a pessoa quis dizer.
module Crm::Memoria::Normal
  module_function

  def chave(texto)
    Autonomia::Agents::Operate::TextoSemDisfarce.normalizado(texto.to_s).unicode_normalize(:nfkd).downcase.delete('^a-z0-9')
  end

  # Valor curto demais ("1", "sim") não se confere: está contido em quase qualquer texto. Fica como sugestão.
  TAMANHO_MINIMO = 4

  def contido?(valor, textos)
    alvo = chave(valor)
    return false if alvo.length < TAMANHO_MINIMO

    Array(textos).any? { |texto| chave(texto).include?(alvo) }
  end

  # O valor numa linha só, sem caracteres invisíveis, no tamanho máximo do fato.
  def linha(texto)
    Autonomia::Agents::Operate::TextoSemDisfarce.normalizado(texto.to_s).squish.first(Crm::MemoriaFato::VALOR_MAXIMO)
  end
end
