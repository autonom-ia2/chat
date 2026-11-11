# Os focos do INPE na base baixada (#2858, F5). Na cidade sem raio: os do código IBGE do município. Com raio, ou com a
# coordenada: um quadrado em volta do ponto pelo índice da latitude, e depois a distância de verdade (haversine). O
# "desde" é o começo do dia, `dias` atrás, no fuso da conta (a `Execucao` roda nele); o dia de cada foco também.
# Nenhum foco: `focos_no_periodo` zero, com `atualizado_em` (o agente diz "nenhum foco até tal dia"). Base com mais de 1 dia (a
# rodada diária falhou): falha `base_desatualizada`, e o agente ouve "não consegui", nunca "nenhum foco".
class Autonomia::FerramentasProntas::Fontes::Queimadas::Inpe < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'inpe'.freeze
  BASE = 'queimadas'.freeze
  MAXIMO = 10
  KM_POR_GRAU = 111.0
  # 1 dia, com folga para a rodada diária terminar (as bases vão uma por vez).
  IDADE_MAXIMA = 26.hours
  Queimadas = Autonomia::FerramentasProntas::Fontes::Queimadas

  def buscar(_consulta, params)
    raise Falha, 'base_desatualizada' if atualizado_em < IDADE_MAXIMA.ago

    latitude, longitude, rotulo, municipio = Queimadas.ponto(params)
    desde = (Time.zone.today - params.fetch('dias', 1)).beginning_of_day
    raio = params['raio_km'] || (municipio ? nil : Queimadas::RAIO_PADRAO)
    focos = raio ? no_raio(desde, latitude, longitude, raio) : no_municipio(desde, municipio)
    com_data(resumo(focos, rotulo, raio, desde))
  end

  private

  def escopo(desde)
    da_base(Autonomia::FerramentasProntas::Bases::FocoDeQueimada).where(detectado_em: desde..)
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
      'onde' => raio ? "até #{raio} km de #{rotulo}" : rotulo, 'desde' => desde.to_date.iso8601,
      # Não é `total`: `total` é o tamanho da lista, e a lista mostra só os `MAXIMO` mais recentes.
      'focos_no_periodo' => focos.size,
      'por_dia' => por_dia(focos),
      'mais_recentes' => focos.first(MAXIMO).map { |foco, km| foco_enxuto(foco, km) }
    }
  end

  # [{ 'data' => '2026-11-11', 'focos' => 377 }, ...], do dia mais recente para o mais antigo. `data` (não `dia`): é o campo
  # que a tela do Experimente usa para identificar cada item da lista.
  def por_dia(focos)
    por_data = focos.group_by { |foco, _km| foco.detectado_em.in_time_zone.to_date.iso8601 }
    por_data.map { |dia, do_dia| { 'data' => dia, 'focos' => do_dia.size } }
  end

  def foco_enxuto(foco, distancia)
    { 'data' => foco.detectado_em.in_time_zone.strftime('%Y-%m-%d %H:%M'), 'latitude' => foco.latitude.to_f,
      'longitude' => foco.longitude.to_f, 'distancia_km' => distancia, 'bioma' => foco.bioma }.compact
  end
end
