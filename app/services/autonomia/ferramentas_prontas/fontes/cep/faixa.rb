# A FAIXA DE NÚMERO de um CEP de rua (#2858, F7, C15c/C15d do testador): o ViaCEP manda no `complemento` de cada CEP
# da rua o pedaço que ele cobre. Os formatos reais (Rua Augusta, São Paulo; Rua Sete de Setembro, Campinas):
#   "até 698 - lado par", "de 700 a 1680 - lado par", "de 2431 ao fim - lado ímpar", "de 611 a 1045", "lado par",
#   "até 1159/1160", e o número exato do CEP de um prédio ("189").
# É o texto fixo dos Correios, não fala de pessoa: lido com `split` e comparação, sem regex. O que não segue esses
# formatos ("2766 Anexo 2770") é nil: não dá para dizer, e quem chama decide.
module Autonomia::FerramentasProntas::Fontes::Cep::Faixa
  SEPARADOR_DO_LADO = ' - '.freeze
  LADO = 'lado'.freeze
  PAR = 'lado par'.freeze
  IMPAR = 'lado impar'.freeze
  INFINITO = Float::INFINITY

  module_function

  # -> true (o número está na faixa), false (fora dela) ou nil (sem faixa, ou texto que não é faixa).
  def cobre?(complemento, numero)
    alvo = Integer(numero.to_s.strip, 10, exception: false)
    texto = Autonomia::FerramentasProntas::Lista.comparavel(complemento)
    return if alvo.nil? || texto.empty?

    trecho, lado = separar(texto)
    return false unless lado_confere?(lado, alvo)

    minimo, maximo = limites(trecho)
    # Só o lado ('lado par') é a rua inteira daquele lado; um trecho que não é faixa ('2766 Anexo 2770 - lado par') não diz.
    return lado && trecho.nil? ? true : nil if minimo.nil?

    alvo.between?(minimo, maximo)
  end

  # O CEP de um prédio: o `complemento` é o próprio número ("1260"), sem faixa nem lado.
  def exato?(complemento, numero)
    alvo = Integer(numero.to_s.strip, 10, exception: false)
    !alvo.nil? && numeros(Autonomia::FerramentasProntas::Lista.comparavel(complemento)) == [alvo]
  end

  # "até 698 - lado par" -> ["até 698", "lado par"]; "lado par" -> [nil, "lado par"].
  def separar(texto)
    return [nil, texto] if texto.start_with?(LADO)

    trecho, lado = texto.split(SEPARADOR_DO_LADO, 2)
    [trecho, lado]
  end

  def lado_confere?(lado, alvo)
    return alvo.even? if lado == PAR
    return alvo.odd? if lado == IMPAR

    true
  end

  # -> [mínimo, máximo] ou nil. "até 698", "de 700 a 1680", "de 2431 ao fim" ou o número exato ("189").
  def limites(trecho)
    palavras = trecho.to_s.split
    case palavras.first
    when 'ate' then de_ate(palavras)
    when 'de' then de_a(palavras)
    else exato(palavras)
    end
  end

  def de_ate(palavras)
    maximo = numeros(palavras[1])&.max
    [0, maximo] if maximo && palavras.size == 2
  end

  # "de 700 a 1680" ou "de 2431 ao fim".
  def de_a(palavras)
    minimo = numeros(palavras[1])&.min
    maximo = ate_onde(palavras[2], palavras[3]) if palavras.size == 4
    [minimo, maximo] if minimo && maximo
  end

  def ate_onde(ligacao, fim)
    return INFINITO if ligacao == 'ao' && fim == 'fim'

    numeros(fim)&.max if ligacao == 'a'
  end

  def exato(palavras)
    numero = numeros(palavras.first)&.first if palavras.one?
    [numero, numero] if numero
  end

  # "1159/1160" -> [1159, 1160]; o que não é número -> nil.
  def numeros(texto)
    valores = texto.to_s.split('/').map { |parte| Integer(parte, 10, exception: false) }
    valores if valores.any? && valores.none?(&:nil?)
  end
end
