# A forma de comparação da seguradora e do número de uma apólice (E4, #2897): "a mesma apólice" não pode depender de
# espaço, caixa, acento ou pontuação ("Seguradora Exemplo S.A." e "seguradora exemplo sa"; "EX-001234" e "ex 001234").
# Fica só letra e dígito, sem acento: a seguradora em minúscula e o número em maiúscula, como o índice único guarda.
# O acento sai pela transliteração do Rails (sempre com as regras de `en`, para a chave não mudar com o idioma de quem
# pede) e o resto por método de texto, sem regex. Texto que não tem letra nem dígito devolve vazio; quem grava recusa
# antes do banco.
module Carteira::Chave
  FORA_LETRA_E_DIGITO = '^a-z0-9'.freeze

  module_function

  def seguradora(texto)
    ActiveSupport::Inflector.transliterate(texto.to_s, locale: :en).downcase.delete(FORA_LETRA_E_DIGITO)
  end

  def numero(texto)
    seguradora(texto).upcase
  end
end
