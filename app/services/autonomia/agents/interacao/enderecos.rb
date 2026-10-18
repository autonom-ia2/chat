# Os endereços que o botão de link pode levar (#1479): só os que o DONO escreveu (instrução, base de conhecimento, o
# que o agente já mandou, saídas das ferramentas do turno), inteiros. A fala do cliente e a memória não contam.
#
# Cada palavra do texto (separada por espaço) que contém "http" (sem diferenciar caixa) vira candidata a partir dali,
# sem a pontuação colada no fim (o ponto final da frase, o parêntese do markdown); quem decide se é endereço é o
# Addressable: http ou https, com host. Sem regex. O pedido do modelo vale só se for IGUAL a um deles depois de normalizar (esquema e host em
# minúsculas, o resto igual): pedaço de endereço, ou endereço a mais, nunca vale.
module Autonomia::Agents::Interacao::Enderecos
  ESQUEMAS = %w[http https].freeze
  PONTUACAO_DO_FIM = ['.', ',', ';', ':', '!', '?', ')', ']', '}', '>', '"', "'", '*', '_'].freeze

  module_function

  # -> Set dos endereços normalizados que aparecem nos textos.
  def dos_textos(textos)
    textos.compact.flat_map { |texto| texto.to_s.split }.filter_map { |palavra| candidato(palavra) }.to_set
  end

  # -> o endereço normalizado, ou nil quando não é http(s) com host.
  def normalizado(endereco)
    return unless endereco.is_a?(String)

    uri = Addressable::URI.parse(endereco)
    return unless ESQUEMAS.include?(uri.scheme.to_s.downcase) && uri.host.present?

    uri.scheme = uri.scheme.downcase
    uri.host = uri.host.downcase
    uri.to_s
  rescue Addressable::URI::InvalidURIError
    nil
  end

  def candidato(palavra)
    inicio = palavra.downcase(:ascii).index('http') # só ASCII: as posições não mudam
    return if inicio.nil?

    endereco = palavra[inicio..]
    endereco = endereco[0...-1] while PONTUACAO_DO_FIM.any? { |sinal| endereco.end_with?(sinal) }
    normalizado(endereco)
  end
end
