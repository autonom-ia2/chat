# ESTAÇÕES DO TEMPO (#2858, F4): as estações meteorológicas automáticas oficiais do INMET mais perto de uma cidade ou
# de uma localização, com a distância.
#   - a fonte só dá a lista inteira das automáticas (`/estacoes/T`, ~260 KB, ~670 estações): ela é a ÚNICA coisa que vai
#     ao INMET e ao cache (os parâmetros são todos locais, então a chave do cache é a mesma para todo pedido: um download
#     por dia para a plataforma inteira). A cidade e a coordenada nunca saem daqui;
#   - a mais perto é calculada aqui, pela distância em linha reta (haversine) da sede do município ou do ponto
#     informado (arredondado a ~110 m, como na Localização). Vão ao modelo as MAX_ESTACOES mais perto, com a situação
#     (a estação em pane não está medindo);
#   - mais longe que MAX_KM de qualquer estação: fora do Brasil, "não encontrado".
# Fonte única (só o INMET publica a rede oficial). Termos: dado aberto do INMET, sem chave e sem limite publicado.
# Cache de 1 dia.
module Autonomia::FerramentasProntas::Fontes::Estacoes
  Parametro = Autonomia::FerramentasProntas::Parametro
  Municipios = Autonomia::FerramentasProntas::Municipios

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  MAX_ESTACOES = 3
  MAX_KM = 400
  MAX_BYTES_INMET = 512.kilobytes

  module_function

  # [latitude, longitude, rótulo] do pedido: a coordenada informada ou a sede do município. nil quando não dá.
  def ponto(params)
    return [params['latitude'], params['longitude'], 'a localização informada'] if params['latitude'] && params['longitude']

    municipio = params['cidade'] && Municipios.buscar(params['uf'], params['cidade'])
    [municipio.latitude, municipio.longitude, municipio.rotulo] if municipio
  end

  # A cidade (a UF sai dela), ou a coordenada inteira. -> o nome do parâmetro que falta (ou a `Falta` da homônima), ou nil.
  def regra(params)
    return if ponto(params)
    return 'longitude' if params['latitude']
    return 'latitude' if params['longitude']

    Municipios.falta(params['uf'], params['cidade'])
  end

  # Uma estação da lista do INMET, enxuta. Sem código, nome ou coordenada: fica de fora.
  def estacao(dado)
    return unless dado.is_a?(Hash)

    latitude = Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada(dado['VL_LATITUDE'], 90)
    longitude = Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada(dado['VL_LONGITUDE'], 180)
    codigo = dado['CD_ESTACAO'].to_s.strip.presence
    nome = dado['DC_NOME'].to_s.squish.presence
    return unless latitude && longitude && codigo && nome

    { 'nome' => nome, 'codigo' => codigo, 'uf' => dado['SG_ESTADO'].to_s.strip.presence,
      'situacao' => dado['CD_SITUACAO'].to_s.squish.presence, 'latitude' => latitude, 'longitude' => longitude }.compact
  end

  def refinar(dados, params)
    latitude, longitude, rotulo = ponto(params)
    perto = Array(dados['estacoes']).map { |item| [item, distancia(latitude, longitude, item)] }.min_by(MAX_ESTACOES, &:last)
    return if perto.empty? || perto.first.last > MAX_KM

    { 'perto_de' => rotulo, 'estacoes' => perto.map { |item, km| item.except('latitude', 'longitude').merge('distancia_km' => km.round(1)) } }
  end

  def distancia(latitude, longitude, item)
    Autonomia::FerramentasProntas::Fontes::Localizacao::Sedes.distancia_km(latitude, longitude, item['latitude'], item['longitude'])
  end

  CIDADE = Parametro.new(nome: 'cidade', local: true, descricao: 'O nome da cidade. Sem cidade: latitude e longitude.',
                         pergunte: 'a cidade (ou peça a localização)') do |valor|
    Parametro.texto_curto(valor)
  end
  UF = Municipios.parametro_uf(local: true)
  LATITUDE = Parametro.new(nome: 'latitude', tipo: 'number', local: true, descricao: 'A latitude da localização que o cliente mandou.') do |valor|
    Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada(valor, 90)
  end
  LONGITUDE = Parametro.new(nome: 'longitude', tipo: 'number', local: true, descricao: 'A longitude da localização que o cliente mandou.') do |valor|
    Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada(valor, 180)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'estacoes', slug: 'pronta_estacoes', nome: 'Estações do tempo', flag: FLAG,
    descricao: 'As estações meteorológicas oficiais do INMET mais perto de uma cidade ou localização, com a distância ' \
               'e se estão funcionando.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'estacoes', descricao: 'as estações oficiais mais perto', opcionais: [CIDADE, UF, LATITUDE, LONGITUDE],
        provedores: [Inmet], validade: 1.day, prazo_por_fonte: 4, prazo_total: 4, regra: method(:regra), refinar: method(:refinar)
      )
    ],
    limite_diario: 500,
    termos: 'INMET (dado aberto, sem chave e sem limite publicado); a lista inteira vai ao cache por 1 dia e a mais ' \
            'perto é calculada aqui. Sem reserva.'
  )
end
