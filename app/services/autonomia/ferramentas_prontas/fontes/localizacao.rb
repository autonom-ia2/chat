# LOCALIZAÇÃO VIRA CIDADE (#2858, F1): a localização que o cliente mandou vira cidade e estado.
#   - principal: Photon (komoot, dados do OpenStreetMap: a resposta leva a atribuição que a licença ODbL pede); o nome
#     só vale se for um município daquele estado;
#   - reserva: a sede de município mais próxima, calculada aqui (`localizacao/sedes.rb`), aproximada e sem cache.
#   O Nominatim fica fora (termo 12 do épico #2858: a política de uso da OSMF).
#   - a coordenada sai ARREDONDADA a 3 casas (~110 m): basta para a cidade e não manda a posição exata do cliente a
#     terceiros. É também a chave do cache (30 dias).
#   - fora do Brasil: "não encontrado".
# Termos: Photon pede uso justo ("uso extenso é limitado"): teto global e cache. Detalhes em
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
    { 'cidade' => cidade }.merge(Autonomia::FerramentasProntas::Ufs.com_nome(sigla)).merge('fonte_dos_dados' => ATRIBUICAO)
  end

  LATITUDE = Parametro.new(nome: 'latitude', tipo: 'number', descricao: 'A latitude da localização que o cliente mandou.',
                           deduza: 'mande latitude e longitude juntas, em número, como vieram na localização que o cliente mandou.') do |valor|
    coordenada(valor, 90)
  end
  LONGITUDE = Parametro.new(nome: 'longitude', tipo: 'number', descricao: 'A longitude da localização que o cliente mandou.',
                            deduza: 'mande latitude e longitude juntas, em número, como vieram na localização que o cliente mandou.') do |valor|
    coordenada(valor, 180)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'localizacao', slug: 'pronta_localizacao', nome: 'Localização vira cidade',
    flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    descricao: 'Diz a cidade e o estado de uma localização (latitude e longitude) que o cliente mandou.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'cidade', descricao: 'a cidade e o estado da localização', obrigatorios: [LATITUDE, LONGITUDE],
        provedores: [Photon, Sedes], validade: 30.days, prazo_por_fonte: 3, prazo_total: 4
      )
    ],
    limite_diario: 500,
    termos: 'Photon (uso justo, atribuição ODbL) e a sede mais próxima calculada aqui. Coordenada arredondada a ~110 m. ' \
            'Cache de 30 dias.'
  )
end
