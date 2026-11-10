# A localização no Nominatim (reserva, OpenStreetMap Foundation), no nível da cidade (`zoom=10`). O estado vem pelo
# código ISO ("BR-SP").
class Autonomia::FerramentasProntas::Fontes::Localizacao::Nominatim < Autonomia::FerramentasProntas::Provedor
  NOME = 'nominatim'.freeze
  HOST = 'nominatim.openstreetmap.org'.freeze
  PREFIXO_ISO = 'BR-'.freeze

  def consultar(_consulta, params)
    dado = objeto!(get("/reverse?format=jsonv2&lat=#{params.fetch('latitude')}&lon=#{params.fetch('longitude')}" \
                       '&zoom=10&accept-language=pt-BR'))
    raise NaoEncontrado if dado.key?('error')

    endereco = objeto!(dado['address'])
    raise NaoEncontrado unless endereco['country_code'].to_s.casecmp?('br')

    Autonomia::FerramentasProntas::Fontes::Localizacao.cidade(cidade(endereco), uf(endereco))
  end

  private

  def cidade(endereco)
    %w[municipality city town village].lazy.filter_map { |campo| texto(endereco[campo]) }.first
  end

  def uf(endereco)
    iso = endereco['ISO3166-2-lvl4'].to_s
    sigla = iso.delete_prefix(PREFIXO_ISO) if iso.start_with?(PREFIXO_ISO)
    sigla if Autonomia::FerramentasProntas::Ufs.nome(sigla)
  end
end
