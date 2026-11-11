# Uma consulta de uma fonte do catálogo (#2858, F0): o que ela responde, os parâmetros (obrigatórios e opcionais), os
# provedores em ordem (o primeiro é o principal, os outros são a reserva), quanto tempo o dado vale no cache e os prazos.
#
# `prazo_por_fonte`: o teto de UMA chamada a um provedor (conexão, cabeçalhos e corpo). `prazo_total`: o teto da
# consulta inteira, somando a reserva; o provedor seguinte só recebe o que sobrou dele.
# `regra`: a conferência entre parâmetros que o schema não expressa (ex.: preço da FIPE pede o código OU marca e
# modelo). Recebe os parâmetros normalizados e devolve o nome do que falta (ou uma `Falta`, com candidatos), ou nil.
# `refinar`: o que roda sobre os dados da fonte (ou do cache) antes de irem ao modelo, com os parâmetros locais (ex.:
# a busca pelo nome do modelo da FIPE). Devolve os dados enxutos, ou nil quando nada sobrou (não encontrado).
# `resolver` (regra "QI 70"): roda depois do limite do dia e antes do cache, e troca o dado que o cliente diz pelo que a
# fonte pede (o nome da marca pelo código dela), com outras consultas da mesma fonte (`Apoio`). Recebe os parâmetros e o
# apoio; devolve [params, nil] ou [nil, a `Falta`] (com os candidatos, quando há mais de um).
class Autonomia::FerramentasProntas::Consulta
  # A folga entre a janela do turno e o prazo da consulta (#2906). O turno espera `ConsultaNoTurno::ESPERA_DO_TURNO`
  # contados do pré-disparo da rodada; o prazo da consulta (`prazo_total`) só começa depois, no job. E o prazo vale POR
  # ETAPA, não como relógio único: o DNS fica fora; a conexão e o TLS têm o `open_timeout` (até 2 s); o `read_timeout`
  # só conta depois da conexão e do TLS. Então a consulta pode passar do `prazo_total` pelo tempo das conexões. A folga
  # cobre as duas coisas: a fila `agent_tools` (com a carga da execução e da ferramenta) E esse excesso da conexão. A
  # consulta que tem de responder no mesmo turno usa `prazo_total <= ESPERA_DO_TURNO - FOLGA_DO_TURNO`. Medido em
  # 11/11/2026 no PNCP (prazo total 7 s), as execuções com as duas chamadas estourando levaram de 7,03 s a 7,14 s.
  # A fila não foi medida em produção: parada ou cheia, ela come mais que a folga, e aí o turno lê "em andamento" e o
  # resultado chega no turno seguinte (#2749).
  FOLGA_DO_TURNO = 1

  attr_reader :nome, :descricao, :obrigatorios, :opcionais, :provedores, :validade, :prazo_por_fonte, :prazo_total

  def initialize(nome:, descricao:, provedores:, validade:, prazo_por_fonte:, prazo_total:, obrigatorios: [], opcionais: [], # rubocop:disable Metrics/ParameterLists
                 regra: nil, refinar: nil, resolver: nil, nao_encontrado: nil)
    @nao_encontrado = nao_encontrado
    @resolver = resolver
    @nome = nome
    @descricao = descricao
    @obrigatorios = obrigatorios
    @opcionais = opcionais
    @provedores = provedores
    @validade = validade
    @prazo_por_fonte = prazo_por_fonte
    @prazo_total = prazo_total
    @regra = regra
    @refinar = refinar
  end

  def parametros
    obrigatorios + opcionais
  end

  # Os argumentos do modelo, normalizados. -> [params, nil] ou [nil, a `Falta` do parâmetro que não serve].
  # O obrigatório que falta e o opcional informado fora do formato são o mesmo erro: nada é consultado.
  def conferir(argumentos)
    normalizados = {}
    parametros.each do |parametro|
      valor = parametro.normalizar(argumentos[parametro.nome])
      return [nil, Autonomia::FerramentasProntas::Falta.de(parametro.nome)] if valor.nil? && exigido?(parametro, argumentos)

      normalizados[parametro.nome] = valor.nil? ? parametro.padrao : valor
    end
    normalizados.compact!
    faltando = @regra&.call(normalizados)
    faltando ? [nil, Autonomia::FerramentasProntas::Falta.de(faltando)] : [normalizados, nil]
  end

  def parametro(nome)
    parametros.find { |parametro| parametro.nome == nome.to_s }
  end

  # O que vai à fonte e identifica o pedido no cache: os parâmetros que não são locais.
  def para_a_fonte(params)
    params.slice(*parametros.reject(&:local?).map(&:nome))
  end

  def chave_do_cache(params)
    para_a_fonte(params).sort.to_h
  end

  # A orientação própria do "não encontrado" (o banco pelo nome comercial), ou nil (vale a da `Resposta`).
  attr_reader :nao_encontrado

  def resolve?
    @resolver.present?
  end

  def resolver(params, apoio)
    @resolver.call(params, apoio)
  end

  def refinar(dados, params)
    @refinar ? @refinar.call(dados, params) : dados
  end

  private

  def exigido?(parametro, argumentos)
    valor = argumentos[parametro.nome]
    obrigatorios.include?(parametro) || !(valor.nil? || (valor.respond_to?(:empty?) && valor.empty?))
  end
end
