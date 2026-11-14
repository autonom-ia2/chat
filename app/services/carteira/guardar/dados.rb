# Os dados de uma apólice na forma do banco, como Carteira::Guardar os recebe (E4, #2897): texto é texto, o valor é
# inteiro em centavos, a data é Date ou texto AAAA-MM-DD. Quem chama é que converte o que leu da planilha, do PDF ou do
# conector: o dado fora da forma é erro de quem chamou (ArgumentError com o nome do campo, nunca com o valor), e não
# chega a ser comparado com o que está guardado. O valor "341000" em texto não é igual ao 341000 guardado, e viraria
# "chegou de novo" a cada chegada.
#
# O que não veio é nil. Qualquer chave fora da lista é ignorada: ninguém cancela nem muda o dono de um seguro por aqui.
module Carteira::Guardar::Dados
  TEXTOS = %i[seguradora seguradora_chave numero numero_chave tipo ramo_original bem].freeze
  DATAS = %i[inicio_vigencia fim_vigencia].freeze
  VALOR = :valor_centavos
  CHAVES = (TEXTOS + DATAS + [VALOR]).freeze

  module_function

  def call(dados)
    recusar(:dados) unless dados.is_a?(Hash)

    dados = dados.symbolize_keys.slice(*CHAVES)
    TEXTOS.each { |campo| recusar(campo) unless dados[campo].nil? || dados[campo].is_a?(String) }
    recusar(VALOR) unless dados[VALOR].nil? || dados[VALOR].is_a?(Integer)
    dados.merge(DATAS.index_with { |campo| data(campo, dados[campo]) })
  end

  def data(campo, valor)
    return valor if valor.nil? || valor.instance_of?(Date)

    recusar(campo) unless valor.is_a?(String)
    Date.iso8601(valor)
  rescue Date::Error
    recusar(campo)
  end

  def recusar(campo)
    raise ArgumentError, campo.to_s
  end
end
