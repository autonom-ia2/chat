# Uma consulta de uma fonte do catálogo (#2858, F0): o que ela responde, os parâmetros (obrigatórios e opcionais), os
# provedores em ordem (o primeiro é o principal, os outros são a reserva), quanto tempo o dado vale no cache e os prazos.
#
# `prazo_por_fonte`: o teto de UMA chamada a um provedor (conexão, cabeçalhos e corpo). `prazo_total`: o teto da
# consulta inteira, somando a reserva; o provedor seguinte só recebe o que sobrou dele.
# `regra`: a conferência entre parâmetros que o schema não expressa (ex.: preço da FIPE pede o código OU marca e
# modelo). Recebe os parâmetros normalizados e devolve o nome do que falta, ou nil.
class Autonomia::FerramentasProntas::Consulta
  attr_reader :nome, :descricao, :obrigatorios, :opcionais, :provedores, :validade, :prazo_por_fonte, :prazo_total

  def initialize(nome:, descricao:, provedores:, validade:, prazo_por_fonte:, prazo_total:, obrigatorios: [], opcionais: [], # rubocop:disable Metrics/ParameterLists
                 regra: nil)
    @nome = nome
    @descricao = descricao
    @obrigatorios = obrigatorios
    @opcionais = opcionais
    @provedores = provedores
    @validade = validade
    @prazo_por_fonte = prazo_por_fonte
    @prazo_total = prazo_total
    @regra = regra
  end

  def parametros
    obrigatorios + opcionais
  end

  # Os argumentos do modelo, normalizados. -> [params, nil] ou [nil, nome do parâmetro que não serve].
  # O obrigatório que falta e o opcional informado fora do formato são o mesmo erro: nada é consultado.
  def conferir(argumentos)
    normalizados = {}
    parametros.each do |parametro|
      valor = parametro.normalizar(argumentos[parametro.nome])
      return [nil, parametro.nome] if valor.nil? && exigido?(parametro, argumentos)

      normalizados[parametro.nome] = valor unless valor.nil?
    end
    faltando = @regra&.call(normalizados)
    faltando ? [nil, faltando] : [normalizados, nil]
  end

  # O que identifica o pedido na fonte: os parâmetros que vão a ela. O filtro local entra também, porque muda a resposta
  # guardada.
  def chave_do_cache(params)
    params.slice(*parametros.map(&:nome)).sort.to_h
  end

  private

  def exigido?(parametro, argumentos)
    valor = argumentos[parametro.nome]
    obrigatorios.include?(parametro) || !(valor.nil? || (valor.respond_to?(:empty?) && valor.empty?))
  end
end
