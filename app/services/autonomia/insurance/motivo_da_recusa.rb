# O MOTIVO DE QUEM NÃO COTOU, EM CATEGORIA, POR MOLDE FECHADO (fatia 2 do #420; decisões do CEO de 13/09/2026).
#
# NENHUM TEXTO DO PORTAL VAI AO MODELO. O conector manda `reason: { kind, text }` (autonomia-adapters#60); o código
# lê o texto e devolve uma categoria fechada, e o modelo recebe só a categoria.
#
# `categoria` devolve `VEICULO` ou `REGIAO` quando, e só quando:
#   1. o `kind` do conector é `risco`, e o texto é String UTF-8 válida;
#   2. TODA palavra do texto, sem acento e em minúsculas, contando palavras de função e números, está no conjunto
#      daquela categoria (`MOLDES`). Uma palavra desconhecida manda para o genérico: é por isso que "Tipo de veículo
#      sem aceitação para o seu código." e "Negativado: CEP sem aceitação." não viram categoria;
#   3. o texto nomeia o que foi recusado: na categoria do veículo, um atributo (idade, ano, modelo, tipo, categoria,
#      tarifária, fabricação) E o veículo (veículo, carro, moto, auto...), porque "idade" e "tipo" sozinhos também
#      servem para a pessoa e para a cobertura; na da região, CEP, localidade, região, circulação ou pernoite.
# Em qualquer outro caso devolve nil, e a Lia diz só que a seguradora não fez proposta. Na dúvida, nil: o erro
# aceitável é o genérico.
module Autonomia::Insurance::MotivoDaRecusa
  KIND_PERMITIDO = 'risco'.freeze
  VEICULO = 'veiculo'.freeze
  REGIAO = 'regiao'.freeze
  CATEGORIAS = [VEICULO, REGIAO].freeze

  # Palavras de função e de recusa, das duas categorias.
  COMUNS = %w[a o as os ao aos de do da dos das e em no na nos nas para por pelo pela com este esta esse essa neste
              nesta nesse nessa deste desta desse dessa nao sem aceito aceita aceitos aceitas aceitacao permitido
              permitida permitidos permitidas possui restrito restrita recusado recusada fora acima atendido
              atendida politica informado informada seguradora].freeze
  ATRIBUTOS_DO_VEICULO = %w[idade ano modelo tipo categoria tarifaria fabricacao].freeze
  NOMES_DO_VEICULO = %w[veiculo veiculos carro carros moto motos motocicleta automovel caminhao onibus auto].freeze
  # A abertura da recusa por risco que o portal escreve ("Cotação não será realizada por motivos técnicos: ...") e a
  # cobertura recusada para o modelo.
  DA_RECUSA_DO_VEICULO = %w[cotacao sera realizada motivos tecnicos cobertura].freeze
  ATRIBUTOS_DA_REGIAO = %w[cep localidade regiao circulacao pernoite].freeze
  DA_REGIAO = %w[local].freeze

  # Por categoria: o conjunto fechado de palavras, e os grupos de que o texto precisa ter ao menos uma palavra cada.
  MOLDES = {
    VEICULO => { palavras: (COMUNS + ATRIBUTOS_DO_VEICULO + NOMES_DO_VEICULO + DA_RECUSA_DO_VEICULO).to_set.freeze,
                 exige: [ATRIBUTOS_DO_VEICULO, NOMES_DO_VEICULO].freeze },
    REGIAO => { palavras: (COMUNS + ATRIBUTOS_DA_REGIAO + DA_REGIAO).to_set.freeze, exige: [ATRIBUTOS_DA_REGIAO].freeze }
  }.freeze
  # A letra que `ActiveSupport::Inflector.transliterate` não sabe escrever vira isto, e a palavra com ela é desconhecida.
  ILEGIVEL = '#'.freeze
  # Uma palavra do texto transliterado: letras, dígitos e a letra ilegível.
  PALAVRA = /[a-z0-9#{ILEGIVEL}]+/

  module_function

  # -> `VEICULO` ou `REGIAO`, ou nil (o genérico).
  def categoria(reason)
    palavras = palavras_de(reason)
    return nil if palavras.blank?

    MOLDES.find { |_categoria, molde| cabe?(palavras, molde) }&.first
  end

  # -> as palavras do texto de um motivo de `kind` `risco`, sem acento e em minúsculas, ou nil.
  def palavras_de(reason)
    return nil unless reason.is_a?(Hash) && reason['kind'] == KIND_PERMITIDO

    texto = reason['text']
    return nil unless texto.is_a?(String) && texto.encoding == Encoding::UTF_8 && texto.valid_encoding?

    ActiveSupport::Inflector.transliterate(texto, ILEGIVEL).downcase.scan(PALAVRA)
  end

  # -> toda palavra está no conjunto do molde, e cada grupo exigido aparece?
  def cabe?(palavras, molde)
    palavras.all? { |palavra| molde[:palavras].include?(palavra) } && molde[:exige].all? { |grupo| palavras.intersect?(grupo) }
  end
end
