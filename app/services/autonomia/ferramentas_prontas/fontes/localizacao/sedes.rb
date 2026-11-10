# A sede de município mais próxima (reserva, sem rede), pela tabela das 5.570 sedes com coordenada
# (`lib/ferramentas_prontas/sedes_municipais.csv`: base "municipios-brasileiros", licença MIT, montada sobre os códigos e
# nomes do IBGE). É uma APROXIMAÇÃO: perto da divisa, o ponto pode ser do município vizinho. A resposta diz isso e não
# vai ao cache (`VALIDADE = 0`), para o Photon responder de novo quando voltar.
# Também serve ao Photon: o nome que ele devolve só vale se for um município daquele estado (`municipio`), porque o
# nome no OpenStreetMap é editável por qualquer pessoa.
class Autonomia::FerramentasProntas::Fontes::Localizacao::Sedes < Autonomia::FerramentasProntas::Provedor
  NOME = 'sedes'.freeze
  HOST = nil
  VALIDADE = 0
  ARQUIVO = Rails.root.join('lib/ferramentas_prontas/sedes_municipais.csv')
  # Mais longe que isto de qualquer sede é fora do Brasil (o maior município, Altamira, tem pontos a ~250 km da sede).
  MAX_KM = 300
  RAIO_DA_TERRA_KM = 6371.0
  OBSERVACAO = 'Aproximado: a sede de município mais próxima do ponto; perto da divisa, confirme a cidade com o cliente.'.freeze

  Sede = Data.define(:uf, :nome, :latitude, :longitude)

  class << self
    def sedes
      @sedes ||= CSV.foreach(ARQUIVO, headers: true).map do |linha|
        Sede.new(uf: linha['uf'], nome: linha['nome'], latitude: linha['latitude'].to_f, longitude: linha['longitude'].to_f)
      end.freeze
    end

    # O nome oficial do município daquela UF com o nome dado (sem acento e sem caixa), ou nil.
    def municipio(uf_sigla, nome)
      alvo = Autonomia::FerramentasProntas::Lista.comparavel(nome)
      return if alvo.empty?

      sedes.find { |sede| sede.uf == uf_sigla && Autonomia::FerramentasProntas::Lista.comparavel(sede.nome) == alvo }&.nome
    end

    def mais_proxima(latitude, longitude)
      sedes.map { |sede| [sede, distancia_km(latitude, longitude, sede.latitude, sede.longitude)] }.min_by(&:last)
    end

    # Distância pelo círculo máximo (haversine), em km.
    def distancia_km(lat1, lon1, lat2, lon2)
      dlat = radianos(lat2 - lat1)
      dlon = radianos(lon2 - lon1)
      a = (Math.sin(dlat / 2)**2) + (Math.cos(radianos(lat1)) * Math.cos(radianos(lat2)) * (Math.sin(dlon / 2)**2))
      2 * RAIO_DA_TERRA_KM * Math.asin(Math.sqrt(a))
    end

    def radianos(graus)
      graus * Math::PI / 180
    end
  end

  def consultar(_consulta, params)
    sede, km = self.class.mais_proxima(params.fetch('latitude'), params.fetch('longitude'))
    raise NaoEncontrado if km > MAX_KM

    Autonomia::FerramentasProntas::Fontes::Localizacao.cidade(sede.nome, sede.uf).merge('observacao' => OBSERVACAO)
  end
end
