# LOCALIZAÇÃO VIRA CIDADE (#2858, F1): a localização que o cliente mandou vira cidade e estado.
#   - principal: Photon (komoot); reserva: Nominatim (OpenStreetMap Foundation). Os dois são o OpenStreetMap: a
#     resposta leva a atribuição que a licença (ODbL) pede.
#   - a coordenada sai ARREDONDADA a 3 casas (~110 m): basta para a cidade e não manda a posição exata do cliente a
#     terceiros. É também a chave do cache (30 dias).
#   - fora do Brasil: "não encontrado".
# Termos: Photon pede uso justo ("uso extenso é limitado"); o Nominatim exige no máximo 1 pedido por segundo, um
# User-Agent que identifique a aplicação, cache, atribuição e poder desligar sem atualizar o software
# (`TetoDoProvedor`: 1 por segundo e a configuração `AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS`). Detalhes e decisão em
# `docs/ferramentas-prontas/termos-das-fontes.md`.
module Autonomia::FerramentasProntas::Fontes::Localizacao
  Parametro = Autonomia::FerramentasProntas::Parametro

  CASAS = 3
  ATRIBUICAO = '© colaboradores do OpenStreetMap (ODbL)'.freeze

  module_function

  def coordenada(valor, limite)
    numero = valor.is_a?(Numeric) ? valor.to_f : Float(valor.to_s.strip, exception: false)
    numero.round(CASAS) if numero&.finite? && numero.abs <= limite
  end

  def cidade(cidade, sigla)
    raise Autonomia::FerramentasProntas::Provedor::NaoEncontrado if cidade.blank? || sigla.blank?

    { 'cidade' => cidade }.merge(Autonomia::FerramentasProntas::Ufs.com_nome(sigla)).merge('fonte_dos_dados' => ATRIBUICAO)
  end

  LATITUDE = Parametro.new(nome: 'latitude', tipo: 'number', descricao: 'A latitude da localização que o cliente mandou.') do |valor|
    coordenada(valor, 90)
  end
  LONGITUDE = Parametro.new(nome: 'longitude', tipo: 'number', descricao: 'A longitude da localização que o cliente mandou.') do |valor|
    coordenada(valor, 180)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'localizacao', slug: 'pronta_localizacao', nome: 'Localização vira cidade',
    flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    descricao: 'Diz a cidade e o estado de uma localização (latitude e longitude) que o cliente mandou.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'cidade', descricao: 'a cidade e o estado da localização', obrigatorios: [LATITUDE, LONGITUDE],
        provedores: [Photon, Nominatim], validade: 30.days, prazo_por_fonte: 3, prazo_total: 6
      )
    ],
    limite_diario: 200,
    termos: 'Photon (uso justo) e Nominatim (1 pedido por segundo, identificação, cache, atribuição, desligável). ' \
            'Coordenada arredondada a ~110 m. Cache de 30 dias.'
  )
end
