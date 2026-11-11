# Os focos do INPE na base baixada (#2858, F5). Na cidade sem raio: os do código IBGE do município. Com raio, ou com a
# coordenada: um quadrado em volta do ponto pelo índice da latitude, e depois a distância de verdade (haversine). O
# "desde" é o começo do dia, `dias` atrás, no fuso da conta (a `Execucao` roda nele); o dia de cada foco também.
class Autonomia::FerramentasProntas::Fontes::Queimadas::Inpe < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'inpe'.freeze
  BASE = 'queimadas'.freeze
  MAXIMO = 10
  KM_POR_GRAU = 111.0
  Queimadas = Autonomia::FerramentasProntas::Fontes::Queimadas

  def consultar(_consulta, params)
    exigir_base!
    latitude, longitude, rotulo, municipio = Queimadas.ponto(params)
    desde = (Time.zone.today - params.fetch('dias', 1)).beginning_of_day
    raio = params['raio_km'] || (municipio ? nil : Queimadas::RAIO_PADRAO)
    focos = raio ? no_raio(desde, latitude, longitude, raio) : no_municipio(desde, municipio)
    raise NaoEncontrado if focos.empty?

    com_data(resumo(focos, rotulo, raio, desde))
  end

  private

  def escopo(desde)
    Autonomia::FerramentasProntas::Bases::FocoDeQueimada.vigente.where(detectado_em: desde..)
  end

  def no_municipio(desde, municipio)
    escopo(desde).where(codigo_municipio: municipio.codigo).order(detectado_em: :desc).map { |foco| [foco, nil] }
  end

  def no_raio(desde, latitude, longitude, raio)
    graus = raio / KM_POR_GRAU
    graus_lon = graus / [Math.cos(latitude * Math::PI / 180).abs, 0.01].max
    perto = escopo(desde).where(latitude: (latitude - graus)..(latitude + graus), longitude: (longitude - graus_lon)..(longitude + graus_lon))
    perto.order(detectado_em: :desc).filter_map do |foco|
      km = Autonomia::FerramentasProntas::Fontes::Localizacao::Sedes.distancia_km(latitude, longitude, foco.latitude.to_f, foco.longitude.to_f)
      [foco, km.round(1)] if km <= raio
    end
  end

  def resumo(focos, rotulo, raio, desde)
    {
      'onde' => raio ? "até #{raio} km de #{rotulo}" : rotulo, 'desde' => desde.to_date.iso8601, 'total' => focos.size,
      'por_dia' => focos.group_by { |foco, _km| foco.detectado_em.in_time_zone.to_date.iso8601 }.transform_values(&:size),
      'mais_recentes' => focos.first(MAXIMO).map { |foco, km| foco_enxuto(foco, km) }
    }
  end

  def foco_enxuto(foco, distancia)
    { 'quando' => foco.detectado_em.in_time_zone.strftime('%Y-%m-%d %H:%M'), 'latitude' => foco.latitude.to_f,
      'longitude' => foco.longitude.to_f, 'distancia_km' => distancia, 'bioma' => foco.bioma }.compact
  end
end
