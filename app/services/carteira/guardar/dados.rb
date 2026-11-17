# Os dados de uma apólice na forma do banco, como Carteira::Guardar os recebe (E4, #2897): texto é texto, o valor é
# inteiro em centavos, a data é Date ou texto AAAA-MM-DD. Quem chama é que converte o que leu da planilha, do PDF ou do
# conector: o dado fora da forma é erro de quem chamou (ArgumentError com o nome do campo, nunca com o valor), e não
# chega a ser comparado com o que está guardado. O valor "341000" em texto não é igual ao 341000 guardado, e viraria
# "chegou de novo" a cada chegada.
#
# O que não veio é nil. Qualquer chave fora da lista é ignorada: ninguém cancela nem muda o dono de um seguro por aqui.
module Carteira::Guardar::Dados
  # E8.1 (#3043): o nascimento do segurado é texto AAAA-MM-DD (a coluna é cifrada), o sexo, o CEP e a placa são texto e a
  # classe de bônus é inteiro. A forma de cada um é do model (Carteira::DadosDoSegurado).
  TEXTOS = %i[seguradora seguradora_chave numero numero_chave tipo ramo_original bem segurado_nascimento segurado_sexo cep placa].freeze
  DATAS = %i[inicio_vigencia fim_vigencia].freeze
  VALOR = :valor_centavos
  INTEIROS = [VALOR, :bonus_classe].freeze
  CHAVES = (TEXTOS + DATAS + INTEIROS).freeze

  module_function

  def call(dados)
    recusar(:dados) unless dados.is_a?(Hash)

    dados = dados.symbolize_keys.slice(*CHAVES)
    da_classe(dados, TEXTOS, String)
    da_classe(dados, INTEIROS, Integer)
    dados.merge(DATAS.index_with { |campo| data(campo, dados[campo]) })
  end

  # Cada campo é nil ou da classe.
  def da_classe(dados, campos, classe)
    campos.each { |campo| recusar(campo) unless dados[campo].nil? || dados[campo].is_a?(classe) }
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
