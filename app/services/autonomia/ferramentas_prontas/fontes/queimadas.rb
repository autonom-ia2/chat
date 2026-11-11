# FOCOS DE QUEIMADA (#2858, F5): "teve queimada perto de Sorriso ontem?". Os focos de calor que os satélites do
# Programa Queimadas do INPE detectaram numa cidade (o município inteiro) ou num raio em volta de um ponto (a sede da
# cidade, ou a localização que o cliente mandou), de `dias` atrás até agora: o total, quantos em cada dia, quando foi o
# último e a distância do mais perto. Foco é detecção de satélite, não confirmação de incêndio no chão; o mesmo fogo pode ser
# visto por mais de um satélite. A base guarda os últimos 8 dias e é baixada pela plataforma todo dia (`Bases::Queimadas`).
module Autonomia::FerramentasProntas::Fontes::Queimadas
  Parametro = Autonomia::FerramentasProntas::Parametro
  Municipios = Autonomia::FerramentasProntas::Municipios

  MAX_DIAS = 7
  MAX_RAIO = 100
  RAIO_PADRAO = 10

  CIDADE = Parametro.new(nome: 'cidade', descricao: 'O nome da cidade. Sem cidade: latitude e longitude.') do |valor|
    Parametro.texto_curto(valor)
  end
  UF = Parametro.new(nome: 'uf', descricao: 'A sigla do estado, quando há cidade com o mesmo nome em outro estado.',
                     opcoes: Autonomia::FerramentasProntas::Ufs::SIGLAS.map(&:downcase))
  LATITUDE = Parametro.new(nome: 'latitude', tipo: 'number', descricao: 'A latitude da localização que o cliente mandou.') do |valor|
    Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada(valor, 90)
  end
  LONGITUDE = Parametro.new(nome: 'longitude', tipo: 'number', descricao: 'A longitude da localização que o cliente mandou.') do |valor|
    Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada(valor, 180)
  end
  RAIO = Parametro.new(nome: 'raio_km', tipo: 'integer',
                       descricao: "Raio em km em volta do ponto (1 a #{MAX_RAIO}). Com cidade e sem raio: o município inteiro.") do |valor|
    Parametro.inteiro(valor, 1..MAX_RAIO)
  end
  DIAS = Parametro.new(nome: 'dias', tipo: 'integer',
                       descricao: "De quantos dias atrás até agora (1 = desde ontem; até #{MAX_DIAS}). Sem valor: 1.") do |valor|
    Parametro.inteiro(valor, 1..MAX_DIAS)
  end

  module_function

  # [latitude, longitude, rótulo, município] do pedido. nil quando não dá.
  def ponto(params)
    return [params['latitude'], params['longitude'], 'a localização informada', nil] if params['latitude'] && params['longitude']

    municipio = params['cidade'] && Municipios.buscar(params['uf'], params['cidade'])
    [municipio.latitude, municipio.longitude, municipio.rotulo, municipio] if municipio
  end

  # A cidade (a UF só quando o `Municipios` não acha sem ela), ou a coordenada inteira (como nas Estações do tempo).
  # -> o parâmetro que falta, ou nil.
  def regra(params)
    return if ponto(params)
    return 'longitude' if params['latitude']
    return 'latitude' if params['longitude']

    params['cidade'] && params['uf'].nil? ? 'uf' : 'cidade'
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'queimadas', slug: 'pronta_queimadas', nome: 'Focos de queimada', flag: Autonomia::FerramentasProntas::Bases::FLAG,
    descricao: 'Os focos de queimada que os satélites do INPE detectaram numa cidade ou perto de uma localização, nos últimos ' \
               'dias (até 7): o total, quantos por dia, quando foi o último e a distância do mais perto (da sede da cidade, ou ' \
               'da localização). Foco é detecção de satélite, não incêndio confirmado. atualizado_em diz de quando é a base.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'focos', descricao: 'os focos detectados; pede cidade (e uf, se houver outra com o mesmo nome), ou latitude e longitude',
        opcionais: [CIDADE, UF, LATITUDE, LONGITUDE, RAIO, DIAS],
        provedores: [Inpe], validade: nil, prazo_por_fonte: 1, prazo_total: 1, regra: method(:regra)
      )
    ],
    limite_diario: 500,
    termos: 'Focos de queimada do Programa Queimadas do INPE (dado aberto), baixados pela plataforma todo dia, 8 dias guardados.'
  )
end
