# Os focos do INPE na base baixada (#2858, F5). Na cidade sem raio: os do código IBGE do município. Com raio, ou com a
# coordenada: um quadrado em volta do ponto pelo índice da latitude, e depois a distância de verdade (haversine). O
# "desde" é o começo do dia, `dias` atrás, no fuso da conta (a `Execucao` roda nele); o dia de cada foco também.
# Dos focos, vão o total, quantos por dia, quando foi o último e a distância do mais perto (da sede da cidade, ou do
# ponto). A lista dos últimos com coordenada e bioma não ia: nenhum leigo lê latitude, e na tela ela virava só "10".
# Nenhum foco: `focos_no_periodo` zero, com `atualizado_em` (o agente diz "nenhum foco até tal dia"). Base com mais de 1 dia (a
# rodada diária falhou): falha `base_desatualizada`, e o agente ouve "não consegui", nunca "nenhum foco".
class Autonomia::FerramentasProntas::Fontes::Queimadas::Inpe < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'inpe'.freeze
  BASE = 'queimadas'.freeze
  KM_POR_GRAU = 111.0
  # 1 dia, com folga para a rodada diária terminar (as bases vão uma por vez).
  IDADE_MAXIMA = 26.hours
  Queimadas = Autonomia::FerramentasProntas::Fontes::Queimadas

  def buscar(_consulta, params)
    raise Falha, 'base_desatualizada' if atualizado_em < IDADE_MAXIMA.ago

    latitude, longitude, rotulo, municipio = Queimadas.ponto(params)
    desde = (Time.zone.today - params.fetch('dias', 1)).beginning_of_day
    raio = params['raio_km'] || (municipio ? nil : Queimadas::RAIO_PADRAO)
    focos = raio ? no_raio(desde, latitude, longitude, raio) : no_municipio(desde, municipio, latitude, longitude)
    com_data(resumo(focos, rotulo, raio, desde))
  end

  private

  def escopo(desde)
    da_base(Autonomia::FerramentasProntas::Bases::FocoDeQueimada).where(detectado_em: desde..)
  end

  # A distância de cada foco do município é medida da sede (o ponto da cidade).
  def no_municipio(desde, municipio, latitude, longitude)
    escopo(desde).where(codigo_municipio: municipio.codigo).order(detectado_em: :desc).map do |foco|
      [foco, distancia(latitude, longitude, foco)]
    end
  end

  def no_raio(desde, latitude, longitude, raio)
    graus = raio / KM_POR_GRAU
    graus_lon = graus / [Math.cos(latitude * Math::PI / 180).abs, 0.01].max
    perto = escopo(desde).where(latitude: (latitude - graus)..(latitude + graus), longitude: (longitude - graus_lon)..(longitude + graus_lon))
    perto.order(detectado_em: :desc).filter_map do |foco|
      km = distancia(latitude, longitude, foco)
      [foco, km] if km <= raio
    end
  end

  def distancia(latitude, longitude, foco)
    Autonomia::FerramentasProntas::Fontes::Localizacao::Sedes.distancia_km(latitude, longitude, foco.latitude.to_f, foco.longitude.to_f).round(1)
  end

  # `focos` vem do mais recente para o mais antigo. Sem foco, sem último nem mais perto.
  def resumo(focos, rotulo, raio, desde)
    ultimo, = focos.first
    {
      'onde' => raio ? "até #{raio} km de #{rotulo}" : rotulo, 'desde' => desde.to_date.iso8601,
      # Não é `total`: na tela, `total` é o tamanho de uma lista.
      'focos_no_periodo' => focos.size,
      'por_dia' => por_dia(focos),
      'ultimo_foco_em' => ultimo&.detectado_em&.in_time_zone&.strftime('%Y-%m-%d %H:%M'),
      'distancia_do_foco_mais_perto_km' => focos.map(&:last).min
    }.compact
  end

  # [{ 'data' => '2026-11-11', 'focos' => 377 }, ...], do dia mais recente para o mais antigo. `data` (não `dia`): é o campo
  # que a tela do Experimente usa para identificar cada item da lista.
  def por_dia(focos)
    por_data = focos.group_by { |foco, _km| foco.detectado_em.in_time_zone.to_date.iso8601 }
    por_data.map { |dia, do_dia| { 'data' => dia, 'focos' => do_dia.size } }
  end
end
